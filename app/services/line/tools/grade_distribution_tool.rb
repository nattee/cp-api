# Grade distribution + course GPA for one course in one term (or all terms of
# a year). Aggregates across ALL curriculum revisions of the course_no.
class Line::Tools::GradeDistributionTool
  DEFINITION = {
    description: "Get the grade distribution (count of students per grade: A, B+, B, ...) and the " \
                 "course GPA (mean/SD over A-F grades) for a course in an academic year, optionally " \
                 "a specific semester. Counts combine all curriculum revisions of the course.",
    parameters: {
      type: "object",
      properties: {
        course_no: {
          type: "string",
          description: "Course number, e.g. '2110327'"
        },
        year: {
          type: "integer",
          description: "Academic year. Buddhist Era (e.g. 2568) or Christian Era (e.g. 2025) accepted; " \
                       "values below 2400 are treated as C.E."
        },
        semester: {
          type: "integer",
          description: "Semester: 1, 2, or 3 (summer). Omit to get every semester of the year."
        }
      },
      required: [ "course_no", "year" ]
    }
  }.freeze

  def self.call(arguments)
    course_no = arguments["course_no"].to_s.strip
    year = arguments["year"].to_i
    return { error: "course_no and year are required" }.to_json if course_no.blank? || year.zero?

    course = Course.where(course_no: course_no).order(revision_year_be: :desc).first
    return { error: "No course found with course_no #{course_no}" }.to_json unless course

    year_ce = year < 2400 ? year : year - 543
    semester = arguments["semester"].presence&.to_i

    base = { course_no: course_no, name_en: course.name, name_th: course.name_th, year_ce: year_ce }
    if semester
      dist = GradeStats::CourseDistribution.call(course_no: course_no, year_ce: year_ce, semester: semester)
      base.merge(dist.except(:course_no, :year_ce)).to_json
    else
      terms = GradeStats::CourseDistribution.call(course_no: course_no, year_ce: year_ce)
      base.merge(semesters: terms.map { |t| t.except(:course_no, :year_ce) }).to_json
    end
  end
end
