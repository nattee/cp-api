module Importers
  class ScheduleImporter < Base
    # Day-of-week parsing: maps various formats to 0-6 (Sun-Sat)
    DAY_MAP = {
      # English full
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6,
      # English abbreviated
      "sun" => 0, "mon" => 1, "tue" => 2, "wed" => 3,
      "thu" => 4, "fri" => 5, "sat" => 6,
      # Two-letter abbreviations
      "su" => 0, "mo" => 1, "tu" => 2, "we" => 3,
      "th" => 4, "fr" => 5, "sa" => 6,
      # Thai
      "อาทิตย์" => 0, "จันทร์" => 1, "อังคาร" => 2, "พุธ" => 3,
      "พฤหัสบดี" => 4, "ศุกร์" => 5, "เสาร์" => 6,
      # Thai abbreviated
      "อา" => 0, "จ" => 1, "อ" => 2, "พ" => 3,
      "พฤ" => 4, "ศ" => 5, "ส" => 6,
      # Numeric (0-based)
      "0" => 0, "1" => 1, "2" => 2, "3" => 3,
      "4" => 4, "5" => 5, "6" => 6
    }.freeze

    def self.attribute_definitions
      [
        { attribute: :course_no,      label: "Course No",      required: true,
          aliases: %w[course_no courseno course_code รหัสวิชา] },
        { attribute: :revision_year,  label: "Revision Year",  required: false,
          aliases: %w[revision_year rev_year ปีหลักสูตร],
          help: "If blank, uses the latest revision of the course." },
        { attribute: :section_number, label: "Section",        required: true,
          aliases: %w[section_number section sec ตอน กลุ่ม] },
        { attribute: :day,            label: "Day",            required: true,
          aliases: %w[day day_of_week วัน],
          help: "Accepts: Mon/Monday/MO/จันทร์/1, etc." },
        { attribute: :start_time,     label: "Start Time",     required: true,
          aliases: %w[start_time start เวลาเริ่ม] },
        { attribute: :end_time,       label: "End Time",       required: true,
          aliases: %w[end_time end เวลาสิ้นสุด] },
        { attribute: :building,       label: "Building",       required: false,
          aliases: %w[building bldg อาคาร] },
        { attribute: :room_number,    label: "Room Number",    required: false,
          aliases: %w[room_number room ห้อง] },
        { attribute: :instructor,     label: "Instructor",     required: false,
          aliases: %w[instructor teacher staff อาจารย์ ผู้สอน] },
        { attribute: :load_ratio,     label: "Load Ratio",     required: false,
          aliases: %w[load_ratio load สัดส่วน],
          help: "0 to 1 (e.g. 0.5 = 50% load). Default 1.0." },
        { attribute: :remark,         label: "Remark",         required: false,
          aliases: %w[remark note หมายเหตุ] },
        { attribute: :semester_id,    label: "Semester",       required: true,
          aliases: [],
          help: "Select the target semester. All rows import into this semester.",
          fixed_options: -> { Semester.ordered.map { |s| ["#{s.display_name} — #{Semester::SEMESTER_LABELS[s.semester_number]}", s.id] } } }
      ]
    end

    # Override the base class call to use find-or-create logic instead of
    # the standard upsert flow. Each row creates/finds nested records
    # (CourseOffering, Section, TimeSlot, Room, Teaching).
    def call
      data_import.update!(state: "processing")

      with_spreadsheet do |spreadsheet|
        col_indices = {}
        data_import.column_mapping.each do |attr_str, labeled_header|
          if labeled_header =~ /\A([A-Z]+): /
            idx = self.class.column_index_from_letter($1)
            col_indices[idx] = attr_str.to_sym
          end
        end

        constants = (data_import.default_values || {}).transform_keys(&:to_sym)

        mapped_attrs = col_indices.values + constants.keys
        missing = self.class.required_attributes - mapped_attrs
        raise "Required fields not mapped: #{missing.join(', ')}" if missing.any?

        row_errors = []
        created = 0
        updated = 0
        unchanged = 0
        skipped = 0
        total = spreadsheet.last_row - 1

        ActiveRecord::Base.transaction do
          (2..spreadsheet.last_row).each do |row_num|
            row = spreadsheet.row(row_num)
            attrs = extract_attributes(row, col_indices)
            constants.each { |attr, value| attrs[attr] = value }

            result = process_row(attrs, row_num)
            case result[:status]
            when :created then created += result[:count]
            when :updated then updated += result[:count]
            when :unchanged then unchanged += 1
            when :skipped then skipped += 1
            when :error
              row_errors << { row: row_num, errors: result[:errors] }
            end
          end

          if row_errors.any? && !data_import.skip_failures
            raise ActiveRecord::Rollback
          end
        end

        if row_errors.any? && !data_import.skip_failures
          data_import.update!(
            state: "failed",
            total_rows: total,
            created_count: 0,
            updated_count: 0,
            unchanged_count: unchanged,
            skipped_count: skipped,
            error_count: row_errors.size,
            row_errors: row_errors
          )
        else
          data_import.update!(
            state: "completed",
            total_rows: total,
            created_count: created,
            updated_count: updated,
            unchanged_count: unchanged,
            skipped_count: skipped,
            error_count: row_errors.size,
            row_errors: row_errors.presence
          )
        end
      end
    rescue => e
      data_import.update!(
        state: "failed",
        error_message: e.message
      )
    end

    private

    # Not used — we override call entirely
    def find_existing_record(_attrs) = nil
    def build_new_record(_attrs) = nil
    def unique_key_fields = []

    def process_row(attrs, row_num)
      # 1. Parse and validate day
      day_of_week = parse_day(attrs[:day])
      return { status: :error, errors: ["Unknown day: #{attrs[:day]}"] } if day_of_week.nil?

      # 2. Parse times
      start_time = parse_time(attrs[:start_time])
      end_time = parse_time(attrs[:end_time])
      return { status: :error, errors: ["Invalid start_time: #{attrs[:start_time]}"] } unless start_time
      return { status: :error, errors: ["Invalid end_time: #{attrs[:end_time]}"] } unless end_time

      # 3. Find course
      course = find_course(attrs[:course_no], attrs[:revision_year])
      return { status: :error, errors: ["Course not found: #{attrs[:course_no]}"] } unless course

      # 4. Find semester
      semester = Semester.find_by(id: attrs[:semester_id])
      return { status: :error, errors: ["Semester not found"] } unless semester

      # 5. Find-or-create CourseOffering
      offering = CourseOffering.find_or_create_by!(course: course, semester: semester) do |co|
        co.status = "planned"
      end

      # 6. Find-or-create Section
      section_number = attrs[:section_number].to_s.gsub(/\.0\z/, "").to_i
      section = offering.sections.find_or_create_by!(section_number: section_number) do |s|
        s.remark = attrs[:remark] if attrs[:remark].present?
      end

      # 7. Find-or-create Room (if building + room_number present)
      room = nil
      building = attrs[:building].to_s.strip.presence
      room_number = attrs[:room_number].to_s.gsub(/\.0\z/, "").strip.presence
      if building && room_number
        room = Room.find_or_create_by!(building: building, room_number: room_number)
      end

      # 8. Find-or-create TimeSlot
      created_count = 0
      updated_count = 0
      time_slot = section.time_slots.find_or_initialize_by(
        day_of_week: day_of_week,
        start_time: start_time,
        end_time: end_time
      )
      time_slot.room = room if room
      if time_slot.new_record?
        time_slot.save!
        created_count += 1
      elsif time_slot.changed?
        time_slot.save!
        updated_count += 1
      end

      # 9. Find-or-create Teaching (if instructor present)
      instructor_name = attrs[:instructor].to_s.strip.presence
      if instructor_name
        staff = find_staff(instructor_name)
        if staff
          load_ratio = attrs[:load_ratio].present? ? attrs[:load_ratio].to_f : 1.0
          teaching = section.teachings.find_or_initialize_by(staff: staff)
          teaching.load_ratio = load_ratio
          if teaching.new_record?
            teaching.save!
            created_count += 1
          elsif teaching.changed?
            teaching.save!
            updated_count += 1
          end
        else
          return { status: :error, errors: ["Instructor not found: #{instructor_name}"] }
        end
      end

      if created_count > 0
        { status: :created, count: created_count }
      elsif updated_count > 0
        { status: :updated, count: updated_count }
      else
        { status: :unchanged }
      end
    rescue ActiveRecord::RecordInvalid => e
      { status: :error, errors: [e.message] }
    end

    def parse_day(value)
      DAY_MAP[value.to_s.strip.downcase]
    end

    def parse_time(value)
      str = value.to_s.strip
      return nil if str.blank?

      # Handle Roo time objects (returned as DateTime/Time for time columns)
      if value.respond_to?(:strftime)
        return Tod::TimeOfDay.new(value.hour, value.min) rescue value
      end

      # Parse HH:MM or H:MM string
      if str =~ /\A(\d{1,2}):(\d{2})\z/
        Time.zone.parse("2000-01-01 #{str}")
      else
        nil
      end
    end

    def find_course(course_no, revision_year)
      no = course_no.to_s.gsub(/\.0\z/, "").strip
      return nil if no.blank?

      if revision_year.present?
        year = revision_year.to_s.gsub(/\.0\z/, "").to_i
        year += 543 if year > 0 && year < 2400
        Course.find_by(course_no: no, revision_year: year)
      else
        # Latest revision
        Course.where(course_no: no).order(revision_year: :desc).first
      end
    end

    def find_staff(name)
      # 1. Exact match on display_name (academic_title + full_name)
      Staff.all.find { |s| s.display_name == name } ||
        # 2. Exact match on full_name
        Staff.find_by("CONCAT(first_name, ' ', last_name) = ?", name) ||
        # 3. Exact match on full_name_th
        Staff.find_by("CONCAT(first_name_th, ' ', last_name_th) = ?", name) ||
        # 4. Partial match (last_name contains)
        Staff.where("last_name LIKE ? OR last_name_th LIKE ?", "%#{name}%", "%#{name}%").first
    end
  end
end
