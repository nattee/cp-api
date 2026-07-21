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
    raise NotImplementedError, "course_enrollment is not implemented yet (eval-only definition)"
  end
end
