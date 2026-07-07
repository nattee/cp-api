require "csv"
require "fileutils"

module Chulabooster
  # Mirrors CB's `program_courses` export (curriculum membership + group tag) into the
  # local program<->course join. Additive and non-destructive, per pairing:
  #   missing locally            -> create with CB tag                 (COMMIT-gated)
  #   exists, local tag blank    -> fill course_group_code/course_type (COMMIT-gated)
  #   exists, tags equal         -> no-op
  #   exists, tags differ        -> report-only, never overwritten
  # Local-only pairings are never touched. Dry-run (default) computes everything,
  # writes CSVs only. Policy: docs/superpowers/specs/2026-07-06-course-group-display-design.md
  class ProgramCourseSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      programs = Program.all.index_by(&:program_code)
      courses  = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      pairings = ProgramCourse.includes(:program, :course)
                              .index_by { |pc| [pc.program_id, pc.course_id] }
      counts = Hash.new(0)
      rows = { created: [], filled: [], disc: [], skipped: [] }

      @client.each_row("program_courses") do |row|
        counts[:cb_rows] += 1
        program = programs[row["program_id"].to_s]
        course  = courses[course_key(row)]
        if program.nil? || course.nil?
          counts[:unresolved] += 1
          rows[:skipped] << [row["program_id"], row["course_id"], row["course_no"],
                             program.nil? ? "program not found" : "course not found"]
          next
        end

        cb_tag = row["course_group_code"].to_s.presence
        pairing = pairings[[program.id, course.id]]
        if pairing.nil?
          create_pairing(program, course, cb_tag, row, counts, rows)
        elsif pairing.course_group_code.to_s == cb_tag.to_s
          counts[:identical] += 1
        elsif pairing.course_group_code.blank?
          fill_tag(pairing, cb_tag, row, counts, rows)
        else
          counts[:tag_discrepancies] += 1
          rows[:disc] << [program.program_code, course.course_no, course.revision_year_be,
                          pairing.course_group_code, cb_tag]
        end
      end

      write_csv("created_pairings.csv", %w[program_code course_no revision_year_be course_group_code], rows[:created])
      write_csv("filled_tags.csv", %w[program_code course_no revision_year_be course_group_code], rows[:filled])
      write_csv("tag_discrepancies.csv", %w[program_code course_no revision_year_be local cb], rows[:disc])
      write_csv("skipped_rows.csv", %w[cb_program_id cb_course_id cb_course_no reason], rows[:skipped])
      counts
    end

    private

    # CB rows carry both course_id ("<CE year><course_no>") and an explicit course_no;
    # prefer the explicit field, as Mappers::ProgramCourses does.
    def course_key(row)
      course_no, rev_be = Convert.parse_course_id(row["course_id"])
      course_no = row["course_no"].to_s if row["course_no"].present?
      [course_no, rev_be]
    end

    def create_pairing(program, course, cb_tag, row, counts, rows)
      pairing = ProgramCourse.new(program: program, course: course,
                                  course_group_code: cb_tag,
                                  course_type: Convert.int_or_nil(row["course_type"]))
      ok = @commit ? pairing.save : pairing.valid?
      unless ok
        counts[:errors] += 1
        rows[:skipped] << [program.program_code, row["course_id"], course.course_no,
                           pairing.errors.full_messages.join("; ")]
        return
      end
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [program.program_code, course.course_no, course.revision_year_be, cb_tag]
    end

    def fill_tag(pairing, cb_tag, row, counts, rows)
      rows[:filled] << [pairing.program.program_code, pairing.course.course_no,
                        pairing.course.revision_year_be, cb_tag]
      counts[@commit ? :filled : :fillable] += 1
      return unless @commit
      pairing.update!(course_group_code: cb_tag,
                      course_type: Convert.int_or_nil(row["course_type"]))
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
