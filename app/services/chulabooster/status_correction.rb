require "csv"
require "fileutils"

module Chulabooster
  # Applies CB's implied status to existing students whose local status disagrees with
  # the already-mirrored cb_status_code. Deliberately separate from StudentSync, which
  # only ever reports this discrepancy — that read-only behavior is a hard invariant
  # (docs/chulabooster-student-status-crosswalk.md: never auto-correct on a routine
  # sync). This is the explicit, human-reviewed correction step: run once per batch the
  # user has actually looked at, not automatically as part of chulabooster:sync_students.
  # Requires sync_students to have run recently enough that cb_status_code is current.
  class StatusCorrection
    def initialize(run_dir:, commit: false)
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      counts = Hash.new(0)
      rows = []

      Student.where.not(cb_status_code: [nil, ""]).find_each do |student|
        counts[:checked] += 1
        implied = StatusCodes.to_local(student.cb_status_code)
        next if implied.nil? || implied == student.status

        rows << [student.student_id, student.status, student.cb_status_code, implied]
        student.update!(status: implied) if @commit
      end

      counts[@commit ? :corrected : :correctable] = rows.size
      write_csv("status_corrections.csv",
                %w[student_id old_status cb_status_code new_status], rows)
      counts
    end

    private

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
