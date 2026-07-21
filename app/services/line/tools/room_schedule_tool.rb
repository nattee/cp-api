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

  def self.call(arguments, user: nil)
    raise NotImplementedError, "room_schedule is not implemented yet (eval-only definition)"
  end
end
