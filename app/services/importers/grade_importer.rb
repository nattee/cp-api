module Importers
  class GradeImporter < Base
    def self.attribute_definitions
      [
        { attribute: :student_id,     label: "Student ID",     required: true,
          aliases: %w[student_id studentid รหัสนิสิต รหัสนักศึกษา] },
        { attribute: :course_code,    label: "Course Code",    required: true,
          aliases: %w[course_id course_code coursecode รหัสวิชา],
          help: "Concatenated field: first 4 digits = revision year, rest = course number. " \
                "Example: 20252110327 → revision year 2025, course 2110327." },
        { attribute: :year,           label: "Year",           required: true,
          aliases: %w[academic_year year ปีการศึกษา] },
        { attribute: :semester,       label: "Semester",       required: true,
          aliases: %w[semester_code semester sem ภาคการศึกษา],
          help: "Accepts 1/2/3 or X1/X2/X3 format." },
        { attribute: :grade,          label: "Grade",          required: false,
          aliases: %w[grade เกรด ผลการเรียน] },
        { attribute: :grade_weight,   label: "Grade Weight",   required: false,
          aliases: %w[grade_weight weight น้ำหนักเกรด] },
        { attribute: :credits_grant,  label: "Credits Granted", required: false,
          aliases: %w[credits_grant credits_granted หน่วยกิตที่ได้] }
      ]
    end

    private

    def find_existing_record(attrs)
      Grade.find_by(
        student_id: attrs[:student_id],
        course_id:  attrs[:course_id],
        year:       attrs[:year],
        semester:   attrs[:semester]
      )
    end

    def build_new_record(attrs)
      Grade.new(attrs)
    end

    def unique_key_fields
      [:student_id, :course_id, :year, :semester]
    end

    def resolve_student(value)
      Student.find_by(student_id: value.to_s.gsub(/\.0\z/, ""))
    end

    def resolve_course(code)
      code_str = code.to_s.gsub(/\.0\z/, "").strip
      return nil if code_str.length <= 4

      revision_year = code_str[0, 4].to_i
      course_no = code_str[4..]

      # 1. Exact match
      exact = Course.find_by(course_no: course_no, revision_year: revision_year)
      return exact if exact

      # 2. Same course_no, closest revision year → copy with "copied" level
      closest = Course.where(course_no: course_no)
                      .order(Arel.sql("ABS(revision_year - #{revision_year.to_i})"))
                      .first
      if closest
        return closest.dup.tap do |copy|
          copy.revision_year = revision_year
          copy.auto_generated = "copied"
          copy.save!
        end
      end

      # 3. Totally unknown → create minimal placeholder
      Course.create!(
        course_no: course_no,
        revision_year: revision_year,
        name: course_no,
        program: Program.placeholder,
        auto_generated: "placeholder"
      )
    end

    # Parse semester_code: accepts "X1"/"X2"/"X3" or plain "1"/"2"/"3"
    def parse_semester(value)
      str = value.to_s.strip.upcase
      str = str.delete_prefix("X") if str.match?(/\AX\d\z/)
      str.to_i
    end

    def transform_attributes(attrs)
      # Extract importer options (prefixed with _) before processing
      blank_grade_action = attrs.delete(:_blank_grade) || "skip"

      # Skip row if grade is blank and action is "skip"
      if blank_grade_action == "skip" && attrs[:grade].blank?
        return nil
      end

      # Coerce numeric fields
      attrs[:year] = attrs[:year].to_i if attrs[:year]
      attrs[:semester] = parse_semester(attrs[:semester]) if attrs[:semester]
      attrs[:credits_grant] = attrs[:credits_grant].to_i if attrs[:credits_grant].present?

      # Look up student
      if attrs.key?(:student_id)
        student_value = attrs.delete(:student_id)
        student = resolve_student(student_value)
        raise "Student not found: #{student_value}" unless student
        attrs[:student_id] = student.id
      end

      # Look up course from concatenated code
      if attrs.key?(:course_code)
        code_value = attrs.delete(:course_code)
        course = resolve_course(code_value)
        raise "Course not found for code: #{code_value}" unless course
        attrs[:course_id] = course.id
      end

      # Auto-derive grade_weight from grade if not provided
      if attrs[:grade].present? && attrs[:grade_weight].blank?
        attrs[:grade_weight] = Grade::GRADE_WEIGHTS[attrs[:grade]]
      end

      # Coerce grade_weight to decimal
      attrs[:grade_weight] = attrs[:grade_weight].to_f if attrs[:grade_weight].present?

      # Mark as imported
      attrs[:source] = "imported"

      attrs
    end
  end
end
