require "csv"
require "fileutils"

# One-time backfill: parses the deprecated per-course `courses.course_group` string
# ("<program_code>-<suffix>", e.g. "3736-ELEC2") into the per-pairing
# program_courses.course_group_code. Run AFTER chulabooster:sync_program_courses so CB
# wins wherever both sources know the answer: fill-blank-only, differing tags are
# report-only. Existing links from these courses to the 0000 placeholder program are
# left alone and reported. Additive — never deletes links or overwrites tags.
# Policy: docs/superpowers/specs/2026-07-06-course-group-display-design.md
class LegacyCourseGroupBackfill
  PATTERN = /\A(\d{4})-(.+)\z/

  def initialize(run_dir:, commit: false)
    @run_dir = run_dir
    @commit = commit
    FileUtils.mkdir_p(@run_dir)
  end

  def call
    programs = Program.all.index_by(&:program_code)
    placeholder = Program.find_by(program_code: "0000")
    counts = Hash.new(0)
    rows = { created: [], filled: [], disc: [], skipped: [], placeholder: [] }

    Course.where.not(course_group: [nil, ""]).find_each do |course|
      counts[:legacy_rows] += 1
      legacy = course.course_group.to_s.strip
      m = PATTERN.match(legacy)
      program = m && programs[m[1]]
      if program.nil?
        counts[:unparseable] += 1
        rows[:skipped] << [course.course_no, course.revision_year_be, legacy,
                           m ? "unknown program code" : "unparseable format"]
        next
      end

      if placeholder && ProgramCourse.exists?(program: placeholder, course: course)
        counts[:placeholder_links] += 1
        rows[:placeholder] << [course.course_no, course.revision_year_be, legacy]
      end

      pairing = ProgramCourse.find_by(program: program, course: course)
      if pairing.nil?
        create_pairing(program, course, legacy, counts, rows)
      elsif pairing.course_group_code.to_s == legacy
        counts[:identical] += 1
      elsif pairing.course_group_code.blank?
        rows[:filled] << [program.program_code, course.course_no, course.revision_year_be, legacy]
        counts[@commit ? :filled : :fillable] += 1
        pairing.update!(course_group_code: legacy) if @commit
      else
        counts[:tag_discrepancies] += 1
        rows[:disc] << [program.program_code, course.course_no, course.revision_year_be,
                        pairing.course_group_code, legacy]
      end
    end

    write_csv("created_pairings.csv", %w[program_code course_no revision_year_be course_group_code], rows[:created])
    write_csv("filled_tags.csv", %w[program_code course_no revision_year_be course_group_code], rows[:filled])
    write_csv("tag_discrepancies.csv", %w[program_code course_no revision_year_be existing legacy], rows[:disc])
    write_csv("skipped_rows.csv", %w[course_no revision_year_be course_group reason], rows[:skipped])
    write_csv("placeholder_links.csv", %w[course_no revision_year_be course_group], rows[:placeholder])
    counts
  end

  private

  def create_pairing(program, course, legacy, counts, rows)
    pairing = ProgramCourse.new(program: program, course: course, course_group_code: legacy)
    ok = @commit ? pairing.save : pairing.valid?
    unless ok
      counts[:errors] += 1
      rows[:skipped] << [course.course_no, course.revision_year_be, legacy,
                         pairing.errors.full_messages.join("; ")]
      return
    end
    counts[@commit ? :created : :creatable] += 1
    rows[:created] << [program.program_code, course.course_no, course.revision_year_be, legacy]
  end

  def write_csv(name, header, data_rows)
    CSV.open(File.join(@run_dir, name), "w") do |csv|
      csv << header
      data_rows.each { |r| csv << r }
    end
  end
end
