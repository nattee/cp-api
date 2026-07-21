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
    raise NotImplementedError, "semester_overview is not implemented yet (eval-only definition)"
  end
end
