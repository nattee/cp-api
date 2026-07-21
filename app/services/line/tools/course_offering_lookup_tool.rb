# Looks up course offerings (the teaching schedule) for a course in a given semester:
# which sections are offered, who teaches each one, and when/where they meet.
#
# This is the tool to use for "who teaches X?" / "what's the schedule for X?" questions.
# course_lookup only returns static course metadata (name, credits, revision) — it does
# NOT know about sections, instructors, or time slots. Those live on CourseOffering →
# Section → Teaching/TimeSlot, which this tool traverses.
#
# A course_no can map to several Course revisions; offerings across all of them are
# returned, grouped by semester (newest first).
class Line::Tools::CourseOfferingLookupTool
  DEFINITION = {
    description: "Look up who teaches a course and its class schedule (sections, instructors, and meeting times) " \
                 "for one or more semesters. Use this for questions like 'who teaches 2110211?', " \
                 "'what sections does this course have?', or 'when does this course meet?'. " \
                 "Search by course number (e.g. '2110211'); optionally restrict to a semester.",
    parameters: {
      type: "object",
      properties: {
        course_no: {
          type: "string",
          description: "Course number, e.g. '2110211' or '2110327'. Required."
        },
        semester: {
          type: "string",
          description: "Semester in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2568/1'. " \
                       "Omit to return all semesters this course was offered in."
        },
        limit: {
          type: "integer",
          description: "Max number of offerings (semesters) to return (default 5, max 20). Newest first."
        }
      },
      required: ["course_no"]
    }
  }.freeze

  MAX_LIMIT = 20
  DEFAULT_LIMIT = 5

  def self.call(arguments, user: nil)
    course_no = arguments["course_no"].to_s.strip
    semester_str = arguments["semester"].to_s.strip.presence
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    return { error: "course_no is required" }.to_json if course_no.blank?

    course_ids = Course.where(course_no: course_no).pluck(:id)
    if course_ids.empty?
      return { offerings: [], total: 0, note: "No course found with course_no '#{course_no}'." }.to_json
    end

    scope = CourseOffering
      .where(course_id: course_ids)
      .includes(:course, :semester, sections: [{ time_slots: :room }, { teachings: :staff }])

    if semester_str
      semester = find_semester(semester_str)
      return { error: "Could not parse semester '#{semester_str}'. Use 'YEAR/NUMBER', e.g. '2568/1'." }.to_json unless semester
      return { offerings: [], total: 0, note: "Course '#{course_no}' has no offering in #{semester_str}." }.to_json unless semester.is_a?(Semester)

      scope = scope.where(semester_id: semester.id)
    end

    offerings = scope.to_a.sort_by { |o| [-o.semester.year_be, -o.semester.semester_number] }
    total = offerings.size
    offerings = offerings.first(limit)

    result = { offerings: offerings.map { |o| serialize(o) }, total: total }
    result[:note] = "Showing #{offerings.size} of #{total} offerings" if total > offerings.size
    result.to_json
  end

  # Returns a Semester, or nil if the string can't be parsed. Returns :missing
  # (truthy, not a Semester) when the format is valid but no such semester exists.
  def self.find_semester(str)
    year, num = str.split("/")
    return nil unless year.present? && num.present?

    Semester.find_by(year_be: year.to_i, semester_number: num.to_i) || :missing
  end
  private_class_method :find_semester

  def self.serialize(offering)
    course = offering.course
    {
      semester: offering.semester.display_name,
      course_no: course.course_no,
      name_en: course.name,
      name_th: course.name_th,
      revision_year: course.revision_year_be,
      status: offering.status,
      sections: offering.sections.sort_by(&:section_number).map { |section| serialize_section(section) }
    }
  end
  private_class_method :serialize

  def self.serialize_section(section)
    {
      section: section.section_number,
      instructors: section.teachings.map { |t| t.staff.display_name_th },
      schedule: section.time_slots
        .sort_by { |ts| [ts.day_of_week, ts.start_time] }
        .map { |ts| format_time_slot(ts) }
    }
  end
  private_class_method :serialize_section

  def self.format_time_slot(time_slot)
    room = time_slot.room ? " @ #{time_slot.room.display_name}" : ""
    "#{time_slot.day_abbr} #{time_slot.time_range}#{room}"
  end
  private_class_method :format_time_slot
end
