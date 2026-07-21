# Enrollment for one course in one year/term: totals and a program × cohort
# breakdown, plus an optional point check for a single student. Counts are
# Grade rows aggregated across ALL curriculum revisions of the course_no
# (same revision-insensitive convention as grade_distribution).
class Line::Tools::CourseEnrollmentTool
  DEFINITION = {
    description: "Get enrollment for a course in an academic year (optionally one semester): how many " \
                 "students took it, broken down by program and admission cohort — and optionally check " \
                 "whether one specific student is enrolled. Counts combine all curriculum revisions. " \
                 "Use for 'how many students take X?', 'which programs take X?', or " \
                 "'did student S enroll in X?'. For counts per grade (A/B+/...) use grade_distribution.",
    parameters: {
      type: "object",
      properties: {
        course_no: {
          type: "string",
          description: "Course number, e.g. '2110327'. Required."
        },
        year: {
          type: "integer",
          description: "Academic year. Buddhist Era (e.g. 2568) or Christian Era (e.g. 2025) accepted; " \
                       "values below 2400 are treated as C.E. Required."
        },
        semester: {
          type: "integer",
          description: "Semester: 1, 2, or 3 (summer). Omit for the whole year."
        },
        student_query: {
          type: "string",
          description: "Student ID or name — check whether this one student is enrolled instead of counting everyone."
        }
      },
      required: [ "course_no", "year" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    course_no = arguments["course_no"].to_s.strip
    year = arguments["year"].to_i
    return { error: "course_no and year are required" }.to_json if course_no.blank? || year.zero?

    year_ce = year < 2400 ? year : year - 543
    semester = arguments["semester"].presence&.to_i

    scope = Grade.joins(:course).where(courses: { course_no: course_no }, year_ce: year_ce)
    scope = scope.where(semester: semester) if semester

    if (student_query = arguments["student_query"].to_s.strip.presence)
      return membership_result(scope, course_no, year_ce, semester, student_query)
    end

    breakdown = scope.joins(student: { program: :program_group })
                     .group("program_groups.code", "students.admission_year_be")
                     .count
                     .map { |(code, admission_year), count|
                       { program: code, admission_year_be: admission_year, count: count } }
                     .sort_by { |row| [ row[:program], row[:admission_year_be] ] }

    {
      course_no: course_no,
      year_be: year_ce + 543,
      semester: semester,
      total: scope.count,
      by_program_cohort: breakdown
    }.to_json
  end

  def self.membership_result(scope, course_no, year_ce, semester, student_query)
    students =
      if student_query.match?(/\A\d+\z/)
        Student.where("student_id LIKE ?", "#{student_query}%")
      else
        like = "%#{student_query}%"
        Student.where("first_name LIKE :q OR last_name LIKE :q OR " \
                      "first_name_th LIKE :q OR last_name_th LIKE :q", q: like)
      end.limit(2).to_a

    return { error: "No student found matching '#{student_query}'" }.to_json if students.empty?
    return { error: "Multiple students match '#{student_query}'. Retry with the exact student ID." }.to_json if students.size > 1

    student = students.first
    rows = scope.where(student_id: student.id).includes(:section).to_a

    {
      course_no: course_no,
      year_be: year_ce + 543,
      semester: semester,
      student: { student_id: student.student_id, name: student.display_name },
      enrolled: rows.any?,
      enrollments: rows.map { |g|
        { term: "#{g.year_ce + 543}/#{g.semester}",
          section: g.section&.section_number,
          grade: g.grade }
      }
    }.to_json
  end
  private_class_method :membership_result
end
