module Scrapers
  class Base
    # Teacher initials in the registration system are only unique WITHIN a
    # faculty (course_no prefix "21" = Engineering, "55" = CULI, ...). Our
    # Staff table holds Engineering people, so initials may only be resolved
    # against courses owned by faculty 21 — CULI's "NNN" is a different person
    # from Engineering's "NNN". Verified 2026-07: schedule self-conflicts plus
    # per-faculty rosters proved every historical cross-faculty match false.
    LOCAL_FACULTY_PREFIX = "21".freeze

    # Genuine outside-faculty teaching assignments go here, as
    # course_no => [initials]. Candidates show up on the scrape page under
    # "Cross-Faculty Matches" — verify with the staff member, then add.
    CROSS_FACULTY_TEACHING_ALLOWLIST = {}.freeze

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

      summary = { sections: 0, time_slots: 0, teachings: 0, unresolved_teachers: [], cross_faculty_matches: [] }

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
          next if start_time.nil? || end_time.nil?

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

            unless resolvable_teacher?(data[:course_no], initials)
              # Foreign-faculty course: a local-staff hit here is (almost
              # always) an initials collision with someone from that faculty.
              # Surface it for review instead of creating a Teaching; codes
              # with no local match are foreign lecturers — not our problem.
              if Staff.exists?(initials: initials)
                summary[:cross_faculty_matches] << { course_no: data[:course_no], initials: initials }
              end
              next
            end

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
      summary[:cross_faculty_matches].uniq!
      summary
    end

    private

    def resolvable_teacher?(course_no, initials)
      course_no.to_s.start_with?(LOCAL_FACULTY_PREFIX) ||
        CROSS_FACULTY_TEACHING_ALLOWLIST.fetch(course_no, []).include?(initials)
    end

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
      return nil if value.blank?
      Time.zone.parse("2000-01-01 #{value}")
    rescue ArgumentError
      nil
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

  class ScraperError < StandardError; end
  class RequestError < StandardError; end
end
