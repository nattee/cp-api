module Scrapers
  class Base
    attr_reader :semester, :study_program

    def initialize(semester:, study_program: "S")
      @semester = semester
      @study_program = study_program
    end

    # Returns a normalized course hash (see docs/schedule-scraper.md), or nil if not found.
    def fetch_course(course_no)
      raise NotImplementedError
    end

    def source_name
      raise NotImplementedError
    end

    # Import a single normalized course hash into the database.
    # Returns a summary hash with counts.
    def import_course_data(data)
      course = Course.find_by(course_no: data[:course_no])
      return { skipped: true, reason: "course not in database" } unless course

      update_course_descriptions(course, data)

      offering = CourseOffering.find_or_create_by!(course: course, semester: semester) do |co|
        co.status = "planned"
      end

      summary = { sections: 0, time_slots: 0, teachings: 0, unresolved_teachers: [] }

      data[:sections].each do |sec_data|
        section = Section.find_or_create_by!(course_offering: offering, section_number: sec_data[:section_no].to_i)
        section.update!(
          enrollment_current: sec_data[:enrollment_current],
          enrollment_max: sec_data[:enrollment_max],
          remark: sec_data[:note]
        )
        summary[:sections] += 1

        sec_data[:classes].each do |cls|
          day = parse_day(cls[:day])
          next if day.nil?

          start_time = parse_time(cls[:start_time])
          end_time = parse_time(cls[:end_time])

          room = find_or_create_room(cls[:building], cls[:room])

          time_slot = TimeSlot.find_or_create_by!(
            section: section,
            day_of_week: day,
            start_time: start_time,
            end_time: end_time
          )
          time_slot.update!(room: room) if room
          summary[:time_slots] += 1

          (cls[:teachers] || []).each do |initials|
            next if initials.blank?
            staff = Staff.find_by(initials: initials)
            if staff
              Teaching.find_or_create_by!(section: section, staff: staff) do |t|
                t.load_ratio = 1.0
              end
              summary[:teachings] += 1
            else
              summary[:unresolved_teachers] << initials
            end
          end
        end
      end

      summary[:unresolved_teachers].uniq!
      summary
    end

    private

    def config
      @config ||= Rails.application.config_for(:scraper)
    end

    DAY_MAP = {
      "SU" => 0, "MO" => 1, "TU" => 2, "WE" => 3,
      "TH" => 4, "FR" => 5, "SA" => 6
    }.freeze

    def parse_day(day_str)
      DAY_MAP[day_str.to_s.upcase]
    end

    def parse_time(value)
      Time.zone.parse("2000-01-01 #{value}")
    end

    def find_or_create_room(building, room_number)
      return nil if building.blank? || room_number.blank?
      Room.find_or_create_by!(building: building, room_number: room_number)
    end

    def update_course_descriptions(course, data)
      updates = {}
      updates[:description] = data[:description_en] if course.description.blank? && data[:description_en].present?
      updates[:description_th] = data[:description_th] if course.description_th.blank? && data[:description_th].present?
      course.update!(updates) if updates.any?
    end
  end
end
