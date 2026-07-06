require "csv"
require "fileutils"

module Chulabooster
  # Phase 2b write path, courses half: mirrors CB's `courses` export into the local catalog.
  # Three buckets per CB row:
  #   CB-only                            -> create with full metadata      (COMMIT-gated)
  #   matched, local auto_generated shell -> backfill from CB, flip "none"  (COMMIT-gated)
  #   matched, local real row             -> field diffs report-only, never written
  # Local-only courses are never touched. Dry-run (default) computes everything, writes CSVs only.
  # Policy + evidence: docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md
  class CourseSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      local = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      counts = Hash.new(0)
      rows = { created: [], backfilled: [], disc: [], errors: [] }

      @client.each_row("courses") do |row|
        counts[:cb_rows] += 1
        key = [row["course_no"].to_s, Convert.ce_to_be(row["revision_year"])]
        course = local[key]
        if course.nil?
          create_course(key, row, counts, rows)
        elsif course.auto_generated != "none"
          backfill_course(course, row, counts, rows)
        else
          report_diffs(course, row, counts, rows)
        end
      end

      write_csv("created_courses.csv", %w[course_no revision_year_be name credits], rows[:created])
      write_csv("backfilled_courses.csv", %w[course_no revision_year_be field old new], rows[:backfilled])
      write_csv("course_discrepancies.csv", %w[course_no revision_year_be field local cb], rows[:disc])
      write_csv("row_errors.csv", %w[course_no revision_year_be errors], rows[:errors])
      counts
    end

    private

    # The synced field set, applied on create AND backfill. name_abbr rides along (CB exports
    # it, the column exists locally) but is excluded from discrepancy comparison — see
    # COMPARED_FIELDS. nl_credits/description stay nil: CB doesn't export the former and the
    # latter is null throughout the export.
    def cb_attributes(row)
      {
        name:      row["course_name"].to_s.strip,
        name_th:   row["course_name_alt"].to_s.strip.presence,
        name_abbr: row["course_name_abbr"].to_s.strip.presence,
        credits:   Convert.int_or_nil(row["credits"]),
        l_credits: Convert.int_or_nil(row["l_credits"]),
        l_hours:   Convert.int_or_nil(row["l_hours"]),
        nl_hours:  Convert.int_or_nil(row["nl_hours"]),
        s_hours:   Convert.int_or_nil(row["s_hours"]),
        is_thesis: Convert.bool(row["is_thesis"]),
        is_gened:  Convert.bool(row["gened"])
      }
    end

    COMPARED_FIELDS = %i[name name_th credits l_credits l_hours nl_hours s_hours
                         is_thesis is_gened].freeze

    def create_course(key, row, counts, rows)
      course = Course.new(course_no: key[0], revision_year_be: key[1],
                          auto_generated: "none", **cb_attributes(row))
      ok = @commit ? course.save : course.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [key[0], key[1], course.errors.full_messages.join("; ")]
        return
      end
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [key[0], key[1], course.name, course.credits]
    end

    # Local shells (auto_generated "placeholder"/"copied") hold no real data — the 2026-07-05
    # crosswalk found every matched-changed course was one of ours. CB's registrar metadata
    # replaces the shell and the row is promoted to auto_generated "none".
    def backfill_course(course, row, counts, rows)
      attrs = cb_attributes(row)
      changes = attrs.filter_map do |field, new_value|
        old_value = course.public_send(field)
        [course.course_no, course.revision_year_be, field, old_value, new_value] if old_value != new_value
      end
      course.assign_attributes(**attrs, auto_generated: "none")
      ok = @commit ? course.save : course.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [course.course_no, course.revision_year_be,
                          course.errors.full_messages.join("; ")]
        course.restore_attributes
        return
      end
      course.restore_attributes unless @commit
      counts[@commit ? :backfilled : :backfillable] += 1
      rows[:backfilled].concat(changes)
    end

    # Real local rows are authoritative: report, never write. (Crosswalk: 65/65 currently
    # identical, so this file is expected empty.)
    def report_diffs(course, row, counts, rows)
      counts[:matched_real] += 1
      cb_attributes(row).slice(*COMPARED_FIELDS).each do |field, cb_value|
        local_value = course.public_send(field)
        next if Convert.norm(local_value) == Convert.norm(cb_value)
        counts[:discrepancies] += 1
        rows[:disc] << [course.course_no, course.revision_year_be, field, local_value, cb_value]
      end
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
