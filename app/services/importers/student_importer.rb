module Importers
  class StudentImporter < Base
    def self.attribute_definitions
      [
        { attribute: :student_id,        label: "Student ID",        required: true,
          aliases: %w[student_id studentid studentcode รหัสนิสิต รหัสนักศึกษา] },
        { attribute: :first_name,        label: "First Name",        required: true,
          aliases: %w[first_name firstname nameenglish ชื่อ] },
        { attribute: :last_name,         label: "Last Name",         required: true,
          aliases: %w[last_name lastname surnameenglish นามสกุล] },
        { attribute: :name_eng,          label: "Full Name (EN)",    required: false,
          aliases: %w[nameeng name_eng ชื่ออังกฤษ],
          help: "\"Title FirstName LastName\" format (e.g. \"Mr. Pawee Laohasinnarong\"). " \
                "Auto-splits into first/last name. Sex is derived from title if not mapped." },
        { attribute: :first_name_th,     label: "First Name (TH)",   required: false,
          aliases: %w[first_name_th firstname_alt ชื่อไทย ชื่อภาษาไทย] },
        { attribute: :last_name_th,      label: "Last Name (TH)",    required: false,
          aliases: %w[last_name_th lastname_alt surnamethai นามสกุลไทย นามสกุลภาษาไทย] },
        { attribute: :name_thai,         label: "Full Name (TH)",    required: false,
          aliases: %w[namethai name_thai ชื่อเต็มไทย],
          help: "\"TitleFirstName LastName\" format (e.g. \"นายปวีร์ เลาหสินณรงค์\"). " \
                "Auto-splits into first/last name. Sex is derived from title if not mapped." },
        { attribute: :sex,               label: "Sex",               required: false,
          aliases: %w[sex gender เพศ] },
        { attribute: :email,             label: "Email",             required: false,
          aliases: %w[email อีเมล] },
        { attribute: :phone,             label: "Phone",             required: false,
          aliases: %w[phone CENSUSTEL โทรศัพท์ เบอร์โทร] },
        { attribute: :address,           label: "Address",           required: false,
          aliases: %w[address ที่อยู่] },
        { attribute: :discord,           label: "Discord",           required: false,
          aliases: %w[discord] },
        { attribute: :line_id,           label: "LINE ID",           required: false,
          aliases: %w[line_id line] },
        { attribute: :guardian_name,     label: "Guardian Name",     required: false,
          aliases: %w[guardian_name ชื่อผู้ปกครอง] },
        { attribute: :guardian_phone,    label: "Guardian Phone",    required: false,
          aliases: %w[guardian_phone เบอร์ผู้ปกครอง] },
        { attribute: :previous_school,   label: "Previous School",   required: false,
          aliases: %w[previous_school โรงเรียนเดิม] },
        { attribute: :tcas,              label: "TCAS Round",        required: false,
          aliases: %w[tcas_round tcas รอบ],
          help: "Accepted values: TCAS1, TCAS2, TCAS3, TCAS4, other, unknown.",
          fixed_options: -> { Student::TCAS_ROUNDS.map { |t| [ t, t ] } } },
        { attribute: :enrollment_method, label: "Enrollment Method", required: false,
          aliases: %w[tcas_project project enrollment_method ประเภทการรับเข้า] },
        { attribute: :admission_year_be,    label: "Admission Year (B.E.)",  required: true,
          aliases: %w[admission_year_be admission_year start_academic_year ปีที่รับเข้า],
          help: "Buddhist Era year (e.g. 2567). CE years (e.g. 2024) are auto-converted by adding 543. " \
                "If not mapped, derived from the first 2 digits of Student ID (e.g. 66xxxxx → 2566)." },
        { attribute: :status,            label: "Status",            required: false,
          aliases: %w[status CURRENT_STATUS สถานะ สถานภาพ],
          fixed_options: -> { Student::STATUSES.map { |s| [ s.humanize, s ] } },
          default_fixed_value: "active" },
        { attribute: :graduation_year_be, label: "Graduation Year (B.E.)", required: false,
          aliases: %w[fromacadyear graduation_year_be graduation_year ปีที่จบ ปีสำเร็จการศึกษา],
          help: "Buddhist Era year (e.g. 2567). CE years (e.g. 2024) are auto-converted by adding 543." },
        { attribute: :degree_level,      label: "Degree Level",      required: false,
          aliases: %w[degree_level degree ระดับ ระดับการศึกษา],
          help: "Used to disambiguate programs with the same name but different degree levels " \
                "(e.g. วิศวกรรมคอมพิวเตอร์ exists at bachelor, master, and doctoral). " \
                "Accepted: ปริญญาตรี, ปริญญาโท, ปริญญาเอก, bachelor, master, doctoral." },
        { attribute: :program_name,      label: "Program",           required: false,
          aliases: %w[coursecodeno program program_name program_id program_code majorcode major หลักสูตร สาขา],
          help: "From file: looks up by program code (4-digit) first, then alternative program code, " \
                "then English name, then Thai name. If multiple programs share the same name, the latest one (by year started) is used.",
          fixed_options: -> { Program.includes(:program_group).order(year_started: :desc).map { |p| [ "#{p.program_group.code} — #{p.program_code} — #{p.name_en} (#{p.year_started})", p.id ] } },
          group_options: -> { ProgramGroup.where.not(code: "OTHER").order(:id).map { |g| [ "#{g.code} — #{g.name_en}", g.id ] } } },
        { attribute: :old_program,       label: "Old Program",       required: false,
          aliases: %w[oldmajor old_program old_major หลักสูตรเดิม] },
        { attribute: :status_note,       label: "Status Note",       required: false,
          aliases: %w[status_note หมายเหตุสถานะ] },
        { attribute: :remark,            label: "Remark",            required: false,
          aliases: %w[remark หมายเหตุ] }
      ]
    end

    def self.derivable_attributes
      %i[first_name last_name admission_year_be]
    end

    THAI_TITLE_PATTERN = /\A(นาย|น\.ส\.|นางสาว|นาง|ด\.ช\.|ด\.ญ\.|เด็กชาย|เด็กหญิง)(.+)/
    ENG_TITLE_PATTERN = /\A(Mr\.|Mrs\.|Miss|Ms\.)\s+(.+)/i

    MALE_TITLES = %w[นาย ด.ช. เด็กชาย Mr.].freeze
    FEMALE_TITLES = %w[น.ส. นางสาว นาง ด.ญ. เด็กหญิง Mrs. Miss Ms.].freeze

    private

    def find_existing_record(attrs)
      Student.find_by(student_id: attrs[:student_id])
    end

    def build_new_record(attrs)
      Student.new(attrs)
    end

    def unique_key_fields
      [ :student_id ]
    end

    def resolve_program(value, admission_year_be: nil, degree_level: nil)
      # Roo reads numeric cells as floats (e.g. 0018 → 18.0), so we
      # strip the decimal suffix for all numeric matching below.
      code = value.to_s.gsub(/\.0\z/, "")

      # 1. Try by program_code (4-digit, zero-padded).
      if code.match?(/\A\d+\z/)
        found = Program.find_by(program_code: code.to_i.to_s.rjust(4, "0"))
        return found if found
      end

      # 2. Try by alternative_program_code (e.g. 5-digit MAJORCODE from reg system).
      #    Multiple programs may share the same alternative code (curriculum revisions).
      #    Pick the latest program that started on or before the student's admission year.
      if code.match?(/\A\d+\z/)
        scope = Program.where(alternative_program_code: code)
        scope = scope.where("year_started <= ?", admission_year_be) if admission_year_be
        found = scope.order(year_started: :desc).first
        return found if found
      end

      # 3. Try by program group code (e.g. "CP", "CEDT", "SE")
      found = resolve_program_by_group(ProgramGroup.find_by(code: value), admission_year_be)
      return found if found

      # 4-5. Try by English/Thai name — degree_level disambiguates when multiple groups share the same name
      group_scope = ProgramGroup.all
      group_scope = group_scope.where(degree_level: degree_level) if degree_level.present?

      found = resolve_program_by_group(group_scope.find_by(name_en: value), admission_year_be)
      return found if found

      resolve_program_by_group(group_scope.find_by(name_th: value), admission_year_be)
    end

    def resolve_program_by_group(group, admission_year_be)
      return nil unless group
      scope = group.programs
      scope = scope.where("year_started <= ?", admission_year_be) if admission_year_be
      scope.order(year_started: :desc).first
    end

    def transform_attributes(attrs)
      attrs[:student_id] = attrs[:student_id].to_s.gsub(/\.0\z/, "") if attrs[:student_id]

      # Split combined name fields into first/last + derive sex from title
      detected_sex = nil
      detected_sex = split_name!(attrs, :name_thai, :first_name_th, :last_name_th, THAI_TITLE_PATTERN) || detected_sex
      detected_sex = split_name!(attrs, :name_eng, :first_name, :last_name, ENG_TITLE_PATTERN) || detected_sex
      attrs[:sex] ||= detected_sex if detected_sex

      # Derive admission year from student ID (first 2 digits + 2500)
      if attrs[:admission_year_be].blank? && attrs[:student_id].present?
        prefix = attrs[:student_id].to_s[0, 2]
        attrs[:admission_year_be] = prefix.to_i + 2500 if prefix.match?(/\A\d{2}\z/)
      end

      # Roo reads numbers as floats — coerce to integer, then auto-detect CE vs BE.
      # BE years are >= 2400 (e.g. 2567), CE years are < 2400 (e.g. 2024).
      # The two ranges never overlap for realistic admission years.
      if attrs[:admission_year_be]
        year = attrs[:admission_year_be].to_i
        year += 543 if year < 2400
        attrs[:admission_year_be] = year
      end

      # Roo reads phone numbers as floats (e.g. 081234567 → 81234567.0).
      # Strip decimal, convert to integer, then zero-pad to at least 9 digits.
      if attrs[:phone].present?
        attrs[:phone] = attrs[:phone].to_s.gsub(/\.0\z/, "").to_i.to_s.rjust(9, "0")
      end

      # Normalize Thai status values to internal status codes.
      # Auto-fill status_note with the original text when it differs from the normalized value.
      if attrs[:status].present?
        original_status = attrs[:status].to_s.strip
        normalized = normalize_status(original_status)
        if attrs[:status_note].blank? && original_status != normalized
          attrs[:status_note] = original_status
        end
        attrs[:status] = normalized
      end

      # Normalize TCAS round
      if attrs[:tcas].present?
        attrs[:tcas] = normalize_tcas(attrs[:tcas].to_s.strip)
      end

      # Default status
      attrs[:status] ||= "active"

      # Cross-fill names: prefer each language's own value, fall back to the other
      attrs[:first_name_th] ||= attrs[:first_name] if attrs[:first_name].present?
      attrs[:last_name_th] ||= attrs[:last_name] if attrs[:last_name].present?
      attrs[:first_name] ||= attrs[:first_name_th] if attrs[:first_name_th].present?
      attrs[:last_name] ||= attrs[:last_name_th] if attrs[:last_name_th].present?

      # Normalize degree_level (transient — used for program resolution only)
      degree_level = attrs.delete(:degree_level)
      if degree_level.present?
        degree_level = normalize_degree_level(degree_level.to_s.strip)
      end

      # Look up program: try ID, then name_en, then name_th (latest by year_started wins)
      if attrs.key?(:program_name)
        program_value = attrs.delete(:program_name).to_s.strip
        if program_value.present?
          program = resolve_program(program_value, admission_year_be: attrs[:admission_year_be], degree_level: degree_level)
          attrs[:program_id] = program&.id
        end
      end

      # Resolve program from program group + admission year
      if attrs.key?(:_program_group_id) && attrs[:program_id].blank?
        group_id = attrs.delete(:_program_group_id).to_i
        if group_id > 0 && attrs[:admission_year_be].present?
          program = Program.where(program_group_id: group_id)
                           .where("year_started <= ?", attrs[:admission_year_be])
                           .order(year_started: :desc)
                           .first
          attrs[:program_id] = program&.id
        end
      end

      # Coerce graduation_year_be: CE→BE auto-convert (same logic as admission_year_be)
      if attrs[:graduation_year_be].present?
        year = attrs[:graduation_year_be].to_i
        year += 543 if year < 2400
        attrs[:graduation_year_be] = year
      end

      attrs
    end

    # Maps Thai status strings from university systems to internal status codes.
    # Exact matches checked first, then prefix patterns for the many "retired" variants.
    STATUS_EXACT = {
      "ลงทะเบียนแรกเข้า" => "active",
      "ไม่จำแนกสภาพนิสิต" => "active",
      "จบการศึกษา" => "graduated",
      "ลาพัก" => "on_leave"
    }.freeze

    # Prefixes that indicate "retired" — covers พ้นสถานภาพลาออก, พ้นสถานภาพไม่มาลงทะเบียน...,
    # พ้นฯเนื่องจาก..., ครบระยะเวลาการศึกษา
    STATUS_ACTIVE_PREFIXES = %w[
      ปกติ
      ลงปกติ
      ขอจบ
      รักษาสถานภาพ
    ].freeze

    STATUS_GRADUATED_PREFIXES = %w[
      สำเร็จการศึก
      เกียรตินิยม
    ].freeze

    STATUS_ON_LEAVE_PREFIXES = %w[
      ลาพักการศึกษา
    ].freeze

    STATUS_RETIRED_PREFIXES = [
      "พ้น",
      "ครบระยะเวลา",
      "ประเมินผลวิทยานิพนธ์ได้u",
      "โครงร่างวิทยานิพนธ์ครบระยะเวลา",
      "การสอบประมวลความรู้ได้รับสัญลักษณ์ U",
      "การสอบวัดคุณสมบัติได้รับสัญลักษณ์ U"
    ].freeze

    DEGREE_LEVEL_MAPPING = {
      "ปริญญาตรี" => "bachelor",
      "ปริญญาโท" => "master",
      "ปริญญาเอก" => "doctoral",
      "bachelor" => "bachelor",
      "master" => "master",
      "doctoral" => "doctoral"
    }.freeze

    def normalize_degree_level(value)
      DEGREE_LEVEL_MAPPING[value] || DEGREE_LEVEL_MAPPING[value.downcase]
    end

    TCAS_EXACT = {
      "สกอ." => "TCAS3",
      "โครงการรับตรง" => "TCAS3",
      "โครงการพิเศษ" => "TCAS3",
      "-" => "unknown"
    }.freeze

    def normalize_tcas(value)
      return TCAS_EXACT[value] if TCAS_EXACT.key?(value)
      value
    end

    def normalize_status(value)
      return STATUS_EXACT[value] if STATUS_EXACT.key?(value)
      return "active" if STATUS_ACTIVE_PREFIXES.any? { |p| value.start_with?(p) }
      return "graduated" if STATUS_GRADUATED_PREFIXES.any? { |p| value.start_with?(p) }
      return "on_leave" if STATUS_ON_LEAVE_PREFIXES.any? { |p| value.start_with?(p) }
      return "retired" if STATUS_RETIRED_PREFIXES.any? { |p| value.start_with?(p) }
      value.downcase.tr(" ", "_")
    end

    # Splits a combined "Title FirstName LastName" field into first/last name attributes.
    # Returns detected sex ("M"/"F") from the title, or nil if no title matched.
    # Only sets first/last if they aren't already provided by direct column mapping.
    def split_name!(attrs, source_key, first_key, last_key, pattern)
      raw = attrs.delete(source_key)
      return nil if raw.blank?

      raw = raw.to_s.strip
      title = nil
      rest = raw

      if raw.match?(pattern)
        match = raw.match(pattern)
        title = match[1]
        rest = match[2].strip
      end

      # Split remainder: last space-separated token is surname, rest is first name
      parts = rest.split(/\s+/, 2)
      if parts.size == 2
        attrs[first_key] ||= parts[0]
        attrs[last_key] ||= parts[1]
      else
        # Single word — put it in first name, leave last name for validation to catch
        attrs[first_key] ||= parts[0]
      end

      # Derive sex from title
      return nil unless title
      return "M" if MALE_TITLES.include?(title)
      return "F" if FEMALE_TITLES.include?(title)
      nil
    end
  end
end
