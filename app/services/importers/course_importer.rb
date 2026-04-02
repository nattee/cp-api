module Importers
  class CourseImporter < Base
    def self.attribute_definitions
      [
        { attribute: :course_no,        label: "Course No",          required: true,
          aliases: %w[course_no course_id รหัสวิชา] },
        { attribute: :revision_year,    label: "Revision Year (B.E.)", required: true,
          aliases: %w[revision_year ปีหลักสูตร],
          help: "Buddhist Era year (e.g. 2566). CE years (e.g. 2023) are auto-converted by adding 543." },
        { attribute: :name,             label: "Name (EN)",          required: true,
          aliases: %w[course_name name ชื่อวิชา] },
        { attribute: :name_th,          label: "Name (TH)",          required: false,
          aliases: %w[course_name_alt name_th ชื่อวิชาไทย] },
        { attribute: :name_abbr,        label: "Abbreviation",       required: false,
          aliases: %w[course_name_abbr name_abbr ชื่อย่อ] },
        { attribute: :course_group,     label: "Course Group",       required: false,
          aliases: %w[course_group_code course_group กลุ่มวิชา] },
        { attribute: :program_name,     label: "Program",            required: false,
          aliases: %w[program_id program_name program หลักสูตร],
          help: "Looks up by ID first, then English name, then Thai name. " \
                "If multiple programs share the same name, the latest one (by year started) is used.",
          fixed_options: -> { Program.includes(:program_group).order(year_started: :desc).map { |p| ["#{p.program_group.code} — #{p.program_code} — #{p.name_en} (#{p.year_started})", p.id] } } },
        { attribute: :is_gened,         label: "GenEd",              required: false,
          aliases: %w[gened is_gened วิชาศึกษาทั่วไป] },
        { attribute: :department_code,  label: "Department Code",    required: false,
          aliases: %w[department_code รหัสภาควิชา] },
        { attribute: :credits,          label: "Credits",            required: false,
          aliases: %w[credits หน่วยกิต] },
        { attribute: :l_credits,        label: "Lecture Credits",    required: false,
          aliases: %w[l_credits หน่วยกิตบรรยาย] },
        { attribute: :nl_credits,       label: "Non-Lecture Credits", required: false,
          aliases: %w[nl_credits หน่วยกิตปฏิบัติ] },
        { attribute: :l_hours,          label: "Lecture Hours",      required: false,
          aliases: %w[l_hours ชั่วโมงบรรยาย] },
        { attribute: :nl_hours,         label: "Non-Lecture Hours",  required: false,
          aliases: %w[nl_hours ชั่วโมงปฏิบัติ] },
        { attribute: :s_hours,          label: "Self-Study Hours",   required: false,
          aliases: %w[s_hours ชั่วโมงศึกษาด้วยตนเอง] },
        { attribute: :is_thesis,        label: "Thesis",             required: false,
          aliases: %w[is_thesis วิทยานิพนธ์] }
      ]
    end

    private

    def find_existing_record(attrs)
      Course.find_by(course_no: attrs[:course_no], revision_year: attrs[:revision_year])
    end

    def build_new_record(attrs)
      Course.new(attrs)
    end

    def unique_key_fields
      [ :course_no, :revision_year ]
    end

    def resolve_program(value)
      str = value.to_s.gsub(/\.0\z/, "").strip
      return nil if str.blank?

      # 1. Try by program_code (4-digit, zero-padded).
      # Roo reads numeric cells as floats (e.g. 0018 → 18.0), so we
      # strip the decimal, convert to integer, then zero-pad to 4 digits.
      if str.match?(/\A\d+\z/)
        found = Program.find_by(program_code: str.to_i.to_s.rjust(4, "0"))
        return found if found
      end

      # 2. Try by English name (latest by year_started)
      found = Program.joins(:program_group).where(program_groups: { name_en: str }).order(year_started: :desc).first
      return found if found

      # 3. Try by Thai name (latest by year_started)
      Program.joins(:program_group).where(program_groups: { name_th: str }).order(year_started: :desc).first
    end

    def coerce_boolean(value)
      case value
      when true, 1, 1.0 then true
      when false, 0, 0.0, nil then false
      else
        str = value.to_s.strip.downcase
        %w[true yes 1 y t ใช่].include?(str)
      end
    end

    def coerce_integer(value)
      return nil if value.nil?
      value.to_f.to_i
    end

    def transform_attributes(attrs)
      # Coerce course_no (Roo may read as float)
      attrs[:course_no] = attrs[:course_no].to_s.gsub(/\.0\z/, "").strip if attrs[:course_no]

      # Coerce integers
      [:revision_year, :credits, :l_credits, :nl_credits, :l_hours, :nl_hours, :s_hours].each do |field|
        attrs[field] = coerce_integer(attrs[field]) if attrs[field]
      end

      # Auto-detect CE vs BE for revision_year (same logic as admission_year_be).
      # BE years are >= 2400 (e.g. 2566), CE years are < 2400 (e.g. 2023).
      if attrs[:revision_year]
        attrs[:revision_year] += 543 if attrs[:revision_year] < 2400
      end

      # Coerce booleans
      attrs[:is_gened] = coerce_boolean(attrs[:is_gened]) if attrs.key?(:is_gened)
      attrs[:is_thesis] = coerce_boolean(attrs[:is_thesis]) if attrs.key?(:is_thesis)

      # Resolve program
      if attrs.key?(:program_name)
        program_value = attrs.delete(:program_name)
        if program_value.present?
          program = resolve_program(program_value)
          attrs[:program_id] = program&.id
        end
      end

      attrs
    end
  end
end
