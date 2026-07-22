module Importers
  # Bulk-loads advisor↔advisee assignments (CSV/Excel: one row per pairing).
  # Rows whose student or staff cannot be resolved are SKIPPED (blank unique
  # key), not errored — re-run after fixing the source data.
  #
  # Modes:
  #   create_only — additive: every resolvable row becomes a new advisorship.
  #   upsert      — per-student snapshot: for students LISTED in the file, the
  #                 blank-End-Date rows are the complete set of current
  #                 advisors; any other current advisorship of those students
  #                 is ended (ended_on = today, history preserved). Students
  #                 absent from the file are untouched. List co-advisors on
  #                 separate rows to keep both.
  #
  # Rows WITH an End Date backfill history: they create (or close) an ended
  # advisorship and never trigger the snapshot reconciliation.
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
          help: "Defaults to today for new advisorships when blank. Existing advisorships keep " \
                "their recorded start date unless the file provides one." },
        { attribute: :ended_on, label: "End Date", required: false,
          aliases: ["end", "end date", "ended on", "วันที่สิ้นสุด"],
          help: "For backfilling history: a row with an end date is recorded as an " \
                "already-ended advisorship and does not count as a current advisor." }
      ]
    end

    private

    def transform_attributes(attrs)
      # Roo reads numeric cells as floats — strip the ".0" before lookup.
      student = Student.find_by(student_id: attrs[:student_id].to_s.gsub(/\.0\z/, ""))
      staff = find_staff(attrs[:staff_name].to_s.strip)

      result = { student_id: student&.id, staff_id: staff&.id }
      # Only carry dates the file actually provides: assigning a default here
      # would overwrite existing rows' started_on on every upsert re-run.
      result[:started_on] = attrs[:started_on] if attrs[:started_on].present?
      result[:ended_on] = attrs[:ended_on] if attrs[:ended_on].present?

      # Blank-End-Date rows assert "this is a current advisor" — they feed the
      # snapshot reconciliation in finalize_sheet. History rows do not.
      if student && staff && result[:ended_on].blank?
        seen_student_ids << student.id
        seen_current_pairs << [ student.id, staff.id ]
      end

      result
    end

    def find_staff(value)
      return nil if value.blank?
      Staff.find_by(initials: value.upcase) ||
        Staff.all.find { |s| s.display_name == value || s.display_name_th == value }
    end

    def find_existing_record(attrs)
      if attrs[:ended_on].present? && attrs[:started_on].present?
        # History backfill naming its start date: match that exact stint first
        # so re-imports are idempotent; fall back to closing the current row.
        Advisorship.find_by(student_id: attrs[:student_id], staff_id: attrs[:staff_id],
                            started_on: attrs[:started_on]) ||
          Advisorship.current.find_by(student_id: attrs[:student_id], staff_id: attrs[:staff_id])
      else
        Advisorship.current.find_by(student_id: attrs[:student_id], staff_id: attrs[:staff_id])
      end
    end

    def build_new_record(attrs)
      Advisorship.new(attrs.reverse_merge(started_on: Date.current))
    end

    def unique_key_fields
      [ :student_id, :staff_id ]
    end

    # Snapshot reconciliation (upsert only): end current advisorships of the
    # students listed in the file whose advisor is not among the file's
    # blank-End-Date rows. Runs inside the sheet transaction; the return value
    # is counted as "updated" by Base.
    def finalize_sheet
      return 0 unless data_import.mode == "upsert" && seen_student_ids.any?

      ended = 0
      Advisorship.current.where(student_id: seen_student_ids.uniq).find_each do |advisorship|
        next if seen_current_pairs.include?([ advisorship.student_id, advisorship.staff_id ])

        advisorship.update!(ended_on: Date.current)
        ended += 1
      end
      seen_student_ids.clear
      seen_current_pairs.clear
      ended
    end

    def seen_student_ids
      @seen_student_ids ||= []
    end

    def seen_current_pairs
      @seen_current_pairs ||= []
    end
  end
end
