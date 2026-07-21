# Summary of one semester's teaching schedule: offering / section / distinct
# course counts and a per-program breakdown. Answers "how many courses are
# offered?" — the per-course view is course_offering_lookup.
class Line::Tools::SemesterOverviewTool
  DEFINITION = {
    description: "Overview of one semester's teaching schedule: how many course offerings, sections, and " \
                 "distinct courses are offered, broken down by program. Use for 'how many courses are " \
                 "offered in 2568/1?' or 'what does this semester look like?'. Defaults to the latest " \
                 "semester. For one specific course's sections use course_offering_lookup.",
    parameters: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "Semester in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2568/1'. Omit for the latest semester."
        }
      },
      required: []
    }
  }.freeze

  def self.call(arguments, user: nil)
    semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
    return semester.to_json unless semester.is_a?(Semester)

    offerings = CourseOffering.where(semester: semester)
    sections = Section.joins(:course_offering).where(course_offerings: { semester_id: semester.id })
    total_offerings = offerings.count

    by_program = offerings.joins(course: { program_courses: { program: :program_group } })
                          .group("program_groups.code")
                          .distinct.count("course_offerings.id")
                          .map { |code, count| { program: code, offerings: count } }
                          .sort_by { |row| row[:program] }

    # The join above only matches offerings whose course has a program_courses
    # pairing. Some offerings (e.g. gen-ed or unpaired electives) have none and
    # would silently vanish from the breakdown, making by_program sum to less
    # than the headline "offerings" total. Surface the gap as an explicit row
    # instead of a self-contradicting number.
    paired = offerings.joins(course: { program_courses: { program: :program_group } })
                      .distinct.count("course_offerings.id")
    unlinked = total_offerings - paired
    by_program << { program: "unlinked", offerings: unlinked } if unlinked.positive?

    {
      semester: semester.display_name,
      offerings: total_offerings,
      sections: sections.count,
      distinct_courses: offerings.joins(:course).distinct.count("courses.course_no"),
      by_program: by_program
    }.to_json
  end
end
