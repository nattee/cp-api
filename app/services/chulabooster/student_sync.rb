require "csv"
require "fileutils"

module Chulabooster
  # Phase 2a write path: creates local Student records for CB-only students and
  # writes report-only discrepancy CSVs for matched students. The ONLY database
  # writes are (a) new Student rows and (b) the mirror column cb_status_code on
  # matched students — both gated behind commit: true. Dry-run (the default)
  # computes everything and writes files only.
  # Policy: docs/chulabooster-program-crosswalk.md, docs/chulabooster-student-status-crosswalk.md.
  class StudentSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      resolver = ProgramResolver.new
      local_by_sid = Student.includes(program: :program_group).index_by { |s| s.student_id.to_s }
      counts = Hash.new(0)
      rows = { created: [], unresolved: [], errors: [], prog_disc: [], status_disc: [], unknown_code: [] }

      @client.each_row("students") do |row|
        local = local_by_sid[row["student_id"].to_s]
        if local
          check_matched(local, row, resolver, counts, rows)
        else
          create_missing(row, resolver, counts, rows)
        end
      end

      write_csv("created_students.csv",
                %w[student_id name program_code group status flags], rows[:created])
      write_csv("unresolved_students.csv",
                %w[student_id major_code admission_year_be reason], rows[:unresolved])
      write_csv("row_errors.csv", %w[student_id errors], rows[:errors])
      write_csv("students_program_discrepancies.csv",
                %w[student_id local_group cb_implied_group flags], rows[:prog_disc])
      write_csv("students_status_discrepancies.csv",
                %w[student_id local_status cb_status_code cb_implied_status], rows[:status_disc])
      write_csv("unknown_status_codes.csv", %w[student_id cb_status_code], rows[:unknown_code])
      counts
    end

    private

    def create_missing(row, resolver, counts, rows)
      counts[:cb_only] += 1
      sid = row["student_id"].to_s

      if row["start_academic_year"].to_s.strip.empty?
        counts[:unresolved] += 1
        rows[:unresolved] << [sid, row["major_code"], nil, "missing start_academic_year"]
        return
      end
      # ce_to_be, not a blind +543: only converts when the value looks like C.E.,
      # so an already-B.E. year from CB can't silently double-convert (review finding).
      admission_year_be = Convert.ce_to_be(row["start_academic_year"])

      result = resolver.resolve(major_code: row["major_code"], student_id: sid,
                                admission_year_be: admission_year_be)
      if result.failure
        counts[:unresolved] += 1
        rows[:unresolved] << [sid, row["major_code"], admission_year_be, result.failure]
        return
      end

      status = StatusCodes.to_local(row["student_status"])
      if status.nil?
        counts[:unknown_status] += 1
        rows[:unknown_code] << [sid, row["student_status"]]
        status = "unknown"
      end

      student = Student.new(
        student_id: sid,
        first_name: row["firstname"].to_s.strip,
        last_name: row["lastname"].to_s.strip,
        first_name_th: row["firstname_alt"].to_s.strip,
        last_name_th: row["lastname_alt"].to_s.strip,
        sex: row["gender"].presence,
        admission_year_be: admission_year_be,
        program: result.program,
        status: status,
        cb_status_code: row["student_status"].to_s
      )
      if result.flags.any?
        # remark is VARCHAR(255); a heuristic + fallback + wide twin tie can exceed it,
        # and under MySQL strict mode an oversized save raises mid-run (review finding).
        student.remark = "ChulaBooster sync #{Date.current}: #{result.flags.join('; ')}".truncate(255)
      end

      ok = @commit ? student.save : student.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [sid, student.errors.full_messages.join("; ")]
        return
      end

      counts[@commit ? :created : :creatable] += 1
      counts[:heuristic_flagged] += 1 if result.heuristic
      counts[:twin_flagged] += 1 if result.twin_tie
      rows[:created] << [sid, "#{student.first_name} #{student.last_name}",
                         result.program.program_code, result.group, status,
                         result.flags.join("; ")]
    end

    def check_matched(local, row, resolver, counts, rows)
      counts[:matched] += 1

      # Program identity: group-level comparison, report-only (local is authoritative).
      # ce_to_be returns nil on a blank year — skip the program check rather than
      # comparing against a garbage year (review finding).
      admission_year_be = Convert.ce_to_be(row["start_academic_year"])
      if admission_year_be
        result = resolver.resolve(major_code: row["major_code"], student_id: local.student_id.to_s,
                                  admission_year_be: admission_year_be)
        local_group = local.program&.program_group&.code
        implied_group = result.failure ? nil : result.group
        if implied_group && local_group && implied_group != local_group
          counts[:program_discrepancies] += 1
          rows[:prog_disc] << [local.student_id, local_group, implied_group, result.flags.join("; ")]
        end
      end

      # Status: CB is the more reliable source here, but still report-only.
      code = row["student_status"].to_s
      implied_status = StatusCodes.to_local(code)
      if implied_status && implied_status != local.status
        counts[:status_discrepancies] += 1
        counts[:stale_active] += 1 if local.status == "active"
        rows[:status_disc] << [local.student_id, local.status, code, implied_status]
      end

      # The one permitted write on existing records: mirror CB's raw code.
      if @commit && local.cb_status_code != code
        local.update_column(:cb_status_code, code)
      end
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
