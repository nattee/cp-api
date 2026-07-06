require "csv"
require "fileutils"
require "set"

module Chulabooster
  # Phase 2b write path, grades half. Streams CB's `student_courses` export against in-memory
  # indexes. Identity key is REVISION-INSENSITIVE — (student_id, course_no, year_ce, semester) —
  # because course_no is the project's cross-revision course identity and 2,181 CB rows
  # reference a different revision of an enrollment we already have (full-key matching would
  # import those as duplicate enrollments). Existing grades are never re-linked to another
  # course revision; only values are corrected.
  #
  # Buckets:
  #   sentinel course_id (FOR_ETL etc.)      -> skip + count
  #   unknown student (non-dept, no CB data) -> skip + report CSV
  #   matched, values identical              -> count
  #   matched, local source "manual"         -> report-only (human data wins)
  #   matched, CB grade blank                -> report-only (never blank local values)
  #   matched, otherwise                     -> CORRECT to CB value (COMMIT-gated; CB is the
  #                                             registrar of record for grade values)
  #   CB-only                                -> create (COMMIT-gated), course via ladder:
  #                                             exact -> closest-revision copy -> placeholder
  # Policy + evidence: docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md
  class GradeSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      build_indexes
      counts = Hash.new(0)
      rows = { created: [], corrections: [], disc: [], skipped: [], ladder: [], errors: [] }

      @client.each_row("student_courses") do |row|
        counts[:cb_rows] += 1
        process_row(row, counts, rows)
      end

      write_csv("created_grades.csv",
                %w[student_id course_no revision_year_be year_ce semester grade credits_grant],
                rows[:created])
      write_csv("grade_corrections.csv",
                %w[student_id course_no year_ce semester old_grade new_grade old_credits_grant new_credits_grant source],
                rows[:corrections])
      write_csv("grade_discrepancies.csv",
                %w[student_id course_no year_ce semester local_grade cb_grade reason], rows[:disc])
      write_csv("skipped_unknown_students.csv",
                %w[student_id course_no year_ce semester grade], rows[:skipped])
      write_csv("ladder_courses.csv",
                %w[course_no revision_year_be kind source_revision_year_be], rows[:ladder])
      write_csv("row_errors.csv", %w[student_id course_no year_ce semester errors], rows[:errors])
      counts
    end

    private

    def build_indexes
      @students = Student.all.index_by { |s| s.student_id.to_s }
      @courses  = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      @by_no    = @courses.values.group_by { |c| c.course_no.to_s }
      @grades   = {}
      Grade.includes(:student, :course).find_each do |g|
        @grades[[g.student.student_id.to_s, g.course.course_no.to_s, g.year_ce, g.semester]] = g
      end
      @created_keys = Set.new
    end

    def process_row(row, counts, rows)
      unless row["course_id"].to_s.match?(/\A\d{4}\d+\z/)
        counts[:sentinel] += 1 # e.g. the FOR_ETL row
        return
      end
      course_no, rev_be = Convert.parse_course_id(row["course_id"])
      sid      = row["student_id"].to_s
      year     = Convert.int_or_nil(row["academic_year"]) # already C.E. — no era conversion
      semester = Convert.semester_number(row["semester_code"])
      key      = [sid, course_no, year, semester]

      student = @students[sid]
      unless student
        # Non-department students absent from CB's own students export — no name/program
        # available, so no Student row can be built. Reported, not imported.
        counts[:unknown_student] += 1
        rows[:skipped] << [sid, course_no, year, semester, row["grade"]]
        return
      end

      if (grade = @grades[key])
        check_matched(grade, row, counts, rows)
      else
        create_grade(key, rev_be, student, row, counts, rows)
      end
    end

    def check_matched(grade, row, counts, rows)
      counts[:matched] += 1
      cb_grade = row["grade"].to_s.strip.presence
      # CB reports credits_grant 0.0 for not-yet-graded enrollments; importing that as
      # "earned 0" would be wrong, so a blank grade forces nil credits.
      cb_credits = cb_grade ? Convert.int_or_nil(row["credits_grant"]) : nil

      if grade.grade == cb_grade && grade.credits_grant == cb_credits
        counts[:identical] += 1
      elsif grade.source == "manual"
        counts[:manual_diff] += 1
        rows[:disc] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                        grade.semester, grade.grade, cb_grade, "manual"]
      elsif cb_grade.nil?
        counts[:value_to_nil] += 1
        rows[:disc] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                        grade.semester, grade.grade, nil, "value_to_nil"]
      else
        correct(grade, cb_grade, cb_credits, counts, rows)
      end
    end

    # CB is the registrar of record for grade values on non-manual rows (crosswalk: the 22
    # current diffs are local interim codes vs CB's resolved finals). nil->value fills the
    # in-progress enrollments this sync creates, on the run after CB grades them.
    def correct(grade, cb_grade, cb_credits, counts, rows)
      rows[:corrections] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                             grade.semester, grade.grade, cb_grade, grade.credits_grant,
                             cb_credits, grade.source]
      unless @commit
        counts[:correctable] += 1
        return
      end
      if grade.update(grade: cb_grade, grade_weight: Grade::GRADE_WEIGHTS[cb_grade],
                      credits_grant: cb_credits)
        counts[:corrected] += 1
      else
        counts[:errors] += 1
        rows[:errors] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                          grade.semester, grade.errors.full_messages.join("; ")]
      end
    end

    def create_grade(key, rev_be, student, row, counts, rows)
      sid, course_no, year, semester = key
      if @created_keys.include?(key)
        counts[:duplicate_cb] += 1
        rows[:errors] << [sid, course_no, year, semester, "duplicate CB row"]
        return
      end

      course = resolve_course(course_no, rev_be, counts, rows)
      cb_grade = row["grade"].to_s.strip.presence
      grade = Grade.new(
        student: student, course: course, year_ce: year, semester: semester,
        grade: cb_grade,
        grade_weight: cb_grade && Grade::GRADE_WEIGHTS[cb_grade],
        credits_grant: cb_grade ? Convert.int_or_nil(row["credits_grant"]) : nil,
        source: "chulabooster"
      )
      ok = @commit ? grade.save : grade.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [sid, course_no, year, semester, grade.errors.full_messages.join("; ")]
        return
      end
      @created_keys << key
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [sid, course_no, course.revision_year_be, year, semester,
                         cb_grade, grade.credits_grant]
    end

    # Exact -> closest-revision copy -> minimal placeholder (the CSV GradeImporter convention,
    # without its program: bug). In dry-run the course is built but not saved; the Grade
    # validity check works against the unsaved object, and the in-memory indexes are updated
    # either way so each missing course is resolved (and reported) exactly once.
    def resolve_course(course_no, rev_be, counts, rows)
      exact = @courses[[course_no, rev_be]]
      return exact if exact

      siblings = @by_no[course_no]
      course =
        if siblings&.any?
          src = siblings.min_by { |c| (c.revision_year_be - rev_be).abs }
          counts[:ladder_copied] += 1
          rows[:ladder] << [course_no, rev_be, "copied", src.revision_year_be]
          src.dup.tap { |c| c.revision_year_be = rev_be; c.auto_generated = "copied" }
        else
          counts[:ladder_placeholder] += 1
          rows[:ladder] << [course_no, rev_be, "placeholder", nil]
          Course.new(course_no: course_no, revision_year_be: rev_be, name: course_no,
                     auto_generated: "placeholder")
        end
      course.save! if @commit
      @courses[[course_no, rev_be]] = course
      (@by_no[course_no] ||= []) << course
      course
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
