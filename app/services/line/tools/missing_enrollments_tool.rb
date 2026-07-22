# Which students of a cohort are MISSING one or more courses — the advisor
# chase-list. Deliberately returns a student roster: the missing-list IS the
# deliverable (unlike course_enrollment, whose counts avoid rosters).
class Line::Tools::MissingEnrollmentsTool
  DEFINITION = {
    description: "Find which students of one admission cohort have NOT enrolled in (or still need) the " \
                 "given course(s). Use for 'who in CP51 hasn't taken 2110327?' or 'which CEDT1 students " \
                 "still need 2110101 and 2110221?'. Returns the missing students (with which of the " \
                 "courses each one is missing) plus per-course counts. Defaults to ACTIVE students only. " \
                 "For enrollment COUNTS of a course use course_enrollment; for top students use cohort_ranking.",
    parameters: {
      type: "object",
      properties: {
        program_code: {
          type: "string",
          description: "Program group code: CP, CEDT, CM, CS, SE, or CD. Required."
        },
        admission_year: {
          type: "integer",
          description: "Admission year. Buddhist Era (e.g. 2565) or Christian Era accepted; values below " \
                       "2400 are treated as C.E. Provide either admission_year or generation. " \
                       "Never derive this from cohort labels like 'CP51' — use generation for those."
        },
        generation: {
          type: "integer",
          description: "Generation/cohort index from labels like 'CP51' or 'รุ่น 51'. The number is a " \
                       "RUNNING INDEX starting at 1, NOT an abbreviated B.E. year. Provide either " \
                       "admission_year or generation."
        },
        course_nos: {
          type: "array",
          items: { type: "string" },
          description: "Course numbers to check, e.g. [\"2110327\"] or [\"2110101\", \"2110221\"]. 1-5 courses. Required."
        },
        mode: {
          type: "string",
          enum: [ "enrolled", "needs_course" ],
          description: "What 'missing' means. 'enrolled' (default): the student has NO enrollment record " \
                       "for the course. 'needs_course': no record OR only failed/withdrawn/unsatisfactory " \
                       "records (F, W, U) — use when the user asks who still NEEDS or must retake a course."
        },
        status: {
          type: "string",
          enum: Student::STATUSES + [ "all" ],
          description: "Cohort status filter. Default 'active'. Use 'all' to include graduated/retired/on-leave students."
        }
      },
      required: [ "program_code", "course_nos" ]
    }
  }.freeze

  MAX_COURSES = 5
  MAX_LISTED = 50
  # Grades that do NOT satisfy a course in needs_course mode. A null grade
  # (enrollment in progress) DOES satisfy — the student doesn't "need" it.
  NON_COUNTING_GRADES = %w[F W U].freeze

  def self.call(arguments, user: nil)
    resolved = Line::Tools::CohortParam.resolve(
      program_code: arguments["program_code"],
      admission_year: arguments["admission_year"],
      generation: arguments["generation"]
    )
    return resolved.to_json if resolved[:error]

    group = resolved[:group]
    year_be = resolved[:admission_year_be]

    course_nos = Array(arguments["course_nos"]).map { |c| c.to_s.strip }.reject(&:empty?).uniq
    return { error: "course_nos is required (1-#{MAX_COURSES} course numbers)" }.to_json if course_nos.empty?
    return { error: "Too many courses — max #{MAX_COURSES} per call" }.to_json if course_nos.size > MAX_COURSES

    unknown = course_nos - Course.where(course_no: course_nos).distinct.pluck(:course_no)
    return { error: "No course found with course_no #{unknown.join(', ')}" }.to_json if unknown.any?

    mode = arguments["mode"].presence || "enrolled"
    return { error: "mode must be 'enrolled' or 'needs_course'" }.to_json unless %w[enrolled needs_course].include?(mode)

    status = arguments["status"].presence || "active"

    students_scope = Student.joins(program: :program_group)
                            .where(program_groups: { id: group.id },
                                   students: { admission_year_be: year_be })
    students_scope = students_scope.where(status: status) unless status == "all"
    students = students_scope.order(:student_id).to_a

    satisfied = course_nos.index_with do |course_no|
      rows = Grade.joins(:course).where(courses: { course_no: course_no },
                                        student_id: students.map(&:id))
      # NOTE: `where.not(grade: NON_COUNTING_GRADES)` would silently EXCLUDE
      # NULL-grade rows too (SQL: NULL != 'F' evaluates to NULL, not true) —
      # wrongly treating in-flight enrollments as not-satisfying. Use an
      # explicit IS NULL OR NOT IN predicate so NULL grades count as satisfied.
      rows = rows.where("grades.grade IS NULL OR grades.grade NOT IN (?)", NON_COUNTING_GRADES) if mode == "needs_course"
      rows.distinct.pluck(:student_id).to_set
    end

    missing = students.filter_map do |student|
      missing_for = course_nos.reject { |no| satisfied[no].include?(student.id) }
      next if missing_for.empty?

      { student_id: student.student_id, name: student.display_name,
        status: student.status, missing: missing_for }
    end

    result = {
      program: group.code,
      admission_year_be: year_be,
      cohort: group.cohort_label(year_be),
      mode: mode,
      status_filter: status,
      cohort_size: students.size,
      per_course: course_nos.map { |no|
        { course_no: no, missing_count: missing.count { |m| m[:missing].include?(no) } }
      },
      missing_total: missing.size,
      students: missing.first(MAX_LISTED)
    }
    result[:note] = "Showing #{MAX_LISTED} of #{missing.size} missing students" if missing.size > MAX_LISTED
    result.to_json
  end
end
