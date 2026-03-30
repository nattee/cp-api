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
        { attribute: :first_name_th,     label: "First Name (TH)",   required: false,
          aliases: %w[first_name_th firstname_alt namethai ชื่อไทย ชื่อภาษาไทย] },
        { attribute: :last_name_th,      label: "Last Name (TH)",    required: false,
          aliases: %w[last_name_th lastname_alt surnamethai นามสกุลไทย นามสกุลภาษาไทย] },
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
        { attribute: :enrollment_method, label: "Enrollment Method", required: false,
          aliases: %w[enrollment_method ประเภทการรับเข้า] },
        { attribute: :admission_year_be,    label: "Admission Year (B.E.)",  required: true,
          aliases: %w[admission_year_be admission_year start_academic_year ปีที่รับเข้า],
          help: "Buddhist Era year (e.g. 2567). CE years (e.g. 2024) are auto-converted by adding 543." },
        { attribute: :status,            label: "Status",            required: false,
          aliases: %w[status สถานะ] },
        { attribute: :graduation_date,   label: "Graduation Date",   required: false,
          aliases: %w[graduation_date วันจบ วันสำเร็จการศึกษา] },
        { attribute: :program_name,      label: "Program",           required: false,
          aliases: %w[program program_name program_id program_code majorcode หลักสูตร],
          help: "From file: looks up by program code (4-digit) first, then alternative program code, " \
                "then English name, then Thai name. If multiple programs share the same name, the latest one (by year started) is used.",
          fixed_options: -> { Program.order(year_started: :desc).map { |p| [ "#{p.program_code} — #{p.name_en} (#{p.year_started})", p.id ] } } }
      ]
    end

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

    def resolve_program(value, admission_year_be: nil)
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

      # 3. Try by English name (latest by year_started)
      found = Program.where(name_en: value).order(year_started: :desc).first
      return found if found

      # 4. Try by Thai name (latest by year_started)
      Program.where(name_th: value).order(year_started: :desc).first
    end

    def transform_attributes(attrs)
      # Roo reads numbers as floats — coerce to integer, then auto-detect CE vs BE.
      # BE years are >= 2400 (e.g. 2567), CE years are < 2400 (e.g. 2024).
      # The two ranges never overlap for realistic admission years.
      if attrs[:admission_year_be]
        year = attrs[:admission_year_be].to_i
        year += 543 if year < 2400
        attrs[:admission_year_be] = year
      end
      attrs[:student_id] = attrs[:student_id].to_s.gsub(/\.0\z/, "") if attrs[:student_id]

      # Default status
      attrs[:status] ||= "active"

      # Model requires Thai names; fall back to English names when not provided
      attrs[:first_name_th] ||= attrs[:first_name] if attrs[:first_name].present?
      attrs[:last_name_th] ||= attrs[:last_name] if attrs[:last_name].present?

      # Look up program: try ID, then name_en, then name_th (latest by year_started wins)
      if attrs.key?(:program_name)
        program_value = attrs.delete(:program_name).to_s.strip
        if program_value.present?
          program = resolve_program(program_value, admission_year_be: attrs[:admission_year_be])
          attrs[:program_id] = program&.id
        end
      end

      # Coerce graduation_date
      if attrs[:graduation_date].present?
        attrs[:graduation_date] = begin
          attrs[:graduation_date].to_date
        rescue
          attrs[:graduation_date]
        end
      end

      attrs
    end
  end
end
