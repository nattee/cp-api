require "csv"

module Exporters
  class ScheduleExporter
    HEADERS = %w[course_no revision_year section_number day start_time end_time building room_number instructor load_ratio remark].freeze
    DAY_ABBRS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

    attr_reader :semester

    def initialize(semester)
      @semester = semester
    end

    def to_csv
      rows = build_rows

      CSV.generate do |csv|
        csv << HEADERS
        rows.each { |row| csv << row }
      end
    end

    def filename
      "schedule_#{semester.year_be}_#{semester.semester_number}.csv"
    end

    private

    def build_rows
      time_slots = TimeSlot.joins(section: { course_offering: [:course, :semester] })
                           .where(course_offerings: { semester_id: semester.id })
                           .includes(:room, section: [:teachings => :staff, course_offering: :course])
                           .order("courses.course_no", "sections.section_number", "time_slots.day_of_week", "time_slots.start_time")

      rows = []

      time_slots.each do |ts|
        section = ts.section
        course = section.course_offering.course
        base = [
          course.course_no,
          course.revision_year,
          section.section_number,
          DAY_ABBRS[ts.day_of_week],
          ts.start_time.strftime("%H:%M"),
          ts.end_time.strftime("%H:%M"),
          ts.room&.building,
          ts.room&.room_number,
        ]

        if section.teachings.any?
          section.teachings.each do |teaching|
            rows << base + [teaching.staff.display_name, teaching.load_ratio, section.remark]
          end
        else
          rows << base + [nil, nil, section.remark]
        end
      end

      rows
    end
  end
end
