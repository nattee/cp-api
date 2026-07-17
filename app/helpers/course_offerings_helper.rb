module CourseOfferingsHelper
  # Registrar-style short name for teacher lists: 3-letter initials when
  # assigned, Thai display name otherwise (same rule as courses/show).
  def staff_short_name(staff)
    staff.initials.presence || staff.display_name_th
  end

  # Plain-text weekly schedule for a section. Slots sharing the same time and
  # room collapse into one segment ("Mon/Wed 09:00-10:30 ENG4-303"); distinct
  # segments join with "; "; roomless slots render "TBA". Returns nil when the
  # section has no time slots. Plain text so the CSV exporter reuses it verbatim.
  def section_schedule_summary(section)
    slots = section.time_slots.sort_by { |ts| [ts.day_of_week, ts.start_time] }
    return nil if slots.empty?

    slots.group_by { |ts| [ts.start_time, ts.end_time, ts.room&.display_name] }
         .map do |(_, _, room_name), group|
           "#{group.map(&:day_abbr).join('/')} #{group.first.time_range} #{room_name || 'TBA'}"
         end
         .join("; ")
  end

  # "45/50" enrollment summary; "?" stands in for a missing side; nil when
  # both sides are missing.
  def section_enrollment_summary(section)
    return nil if section.enrollment_current.nil? && section.enrollment_max.nil?
    "#{section.enrollment_current || '?'}/#{section.enrollment_max || '?'}"
  end
end
