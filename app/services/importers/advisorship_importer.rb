module Importers
  # Bulk-loads advisor↔advisee assignments (CSV/Excel: one row per pairing).
  # Rows whose student or staff cannot be resolved are SKIPPED (blank unique
  # key), not errored — re-run after fixing the source data and the found
  # rows upsert idempotently against the current advisorship for the pair.
  class AdvisorshipImporter < Base
    def self.attribute_definitions
      [
        { attribute: :student_id, label: "Student ID", required: true,
          aliases: ["student id", "student_id", "id", "รหัสนิสิต", "เลขประจำตัวนิสิต"] },
        { attribute: :staff_name, label: "Advisor", required: true,
          aliases: ["advisor", "advisor name", "staff", "อาจารย์ที่ปรึกษา", "ที่ปรึกษา"],
          help: "Matched against staff initials (e.g. NNN), then English name, then Thai name." },
        { attribute: :started_on, label: "Start Date", required: false,
          aliases: ["start", "start date", "started on", "วันที่เริ่ม"],
          help: "Defaults to today when blank." }
      ]
    end

    private

    def transform_attributes(attrs)
      # Roo reads numeric cells as floats — strip the ".0" before lookup.
      student = Student.find_by(student_id: attrs[:student_id].to_s.gsub(/\.0\z/, ""))
      staff = find_staff(attrs[:staff_name].to_s.strip)

      {
        student_id: student&.id,
        staff_id: staff&.id,
        started_on: attrs[:started_on].presence || Date.current
      }
    end

    def find_staff(value)
      return nil if value.blank?
      Staff.find_by(initials: value.upcase) ||
        Staff.all.find { |s| s.display_name == value || s.display_name_th == value }
    end

    def find_existing_record(attrs)
      Advisorship.current.find_by(student_id: attrs[:student_id], staff_id: attrs[:staff_id])
    end

    def build_new_record(attrs)
      Advisorship.new(attrs)
    end

    def unique_key_fields
      [:student_id, :staff_id]
    end
  end
end
