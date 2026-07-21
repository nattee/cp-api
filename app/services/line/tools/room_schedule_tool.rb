# Weekly class schedule of one room for a semester, mirroring the room
# report (SchedulesController#room) as compact JSON.
class Line::Tools::RoomScheduleTool
  DEFINITION = {
    description: "Get a room's weekly class schedule for a semester: which courses/sections meet there, " \
                 "on which days and times, and who teaches. Use for 'what's in room ENG4-303?' or " \
                 "'is room X free on Tuesday?'. Search by room name ('ENG4-303'), building ('ENG4'), " \
                 "or room number ('303'). Defaults to the latest semester. " \
                 "To find where a COURSE meets, use course_offering_lookup instead.",
    parameters: {
      type: "object",
      properties: {
        room: {
          type: "string",
          description: "Room name ('ENG4-303'), building ('ENG4'), or room number ('303'). Required."
        },
        semester: {
          type: "string",
          description: "Semester in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2568/1'. Omit for the latest semester."
        },
        day: {
          type: "string",
          description: "Optional weekday filter, English name or abbreviation, e.g. 'Tuesday' or 'Tue'."
        }
      },
      required: [ "room" ]
    }
  }.freeze

  MAX_MATCH_CHOICES = 10

  def self.call(arguments, user: nil)
    room_query = arguments["room"].to_s.strip
    return { error: "room is required" }.to_json if room_query.blank?

    rooms = Room.where(
      "CONCAT(building, '-', room_number) LIKE :q OR building LIKE :q OR room_number LIKE :q",
      q: "%#{room_query}%"
    ).order(:building, :room_number).to_a

    return { error: "No room found matching '#{room_query}'" }.to_json if rooms.empty?
    if rooms.size > 1
      return {
        error: "Multiple rooms match '#{room_query}'. Retry with the full room name.",
        matches: rooms.first(MAX_MATCH_CHOICES).map(&:display_name)
      }.to_json
    end
    room = rooms.first

    semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
    return semester.to_json unless semester.is_a?(Semester)

    day_index = nil
    if (day_str = arguments["day"].to_s.strip.presence)
      day_index = TimeSlot::DAY_NAMES.index { |name| name.downcase.start_with?(day_str.downcase) }
      return { error: "Could not parse day '#{day_str}'. Use an English day name like 'Tuesday' or 'Tue'." }.to_json unless day_index
    end

    slots = TimeSlot.where(room: room)
                    .joins(section: :course_offering)
                    .where(course_offerings: { semester_id: semester.id })
                    .includes(section: [ { teachings: :staff }, { course_offering: :course } ])
    slots = slots.where(day_of_week: day_index) if day_index

    entries = slots.sort_by { |ts| [ ts.day_of_week, ts.start_time ] }.map do |ts|
      offering = ts.section.course_offering
      {
        day: ts.day_name,
        time: ts.time_range,
        course_no: offering.course.course_no,
        name: offering.course.name,
        section: ts.section.section_number,
        instructors: ts.section.teachings.map { |t| t.staff.display_name_th }
      }
    end

    result = {
      room: room.display_name,
      semester: semester.display_name,
      capacity: room.capacity,
      room_type: room.room_type,
      entries: entries
    }
    result[:note] = "No classes scheduled in this room for #{semester.display_name}." if entries.empty?
    result.to_json
  end
end
