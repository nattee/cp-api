require "csv"

module Book30
  # Turns the book's directory into book30_entries + placeholder students.
  # Dry-run by default: everything runs inside a transaction that is rolled back unless
  # commit: true, so the dry-run sees exactly what the commit would (including the CM
  # re-file). Reports land in out_dir either way.
  class Importer
    CM_REFILE = { from: "0018", to: "0037", years: (2535..2538), id_prefix: "C" }.freeze

    def initialize(pdf_path: nil, directory: nil, commit: false,
                   out_dir: Rails.root.join("tmp", "book30_import", Time.current.strftime("%Y%m%d-%H%M%S")), io: $stdout)
      @directory = directory || Directory.from_pdf(pdf_path || Directory::DEFAULT_PDF)
      @commit = commit
      @out_dir = Pathname(out_dir)
      @io = io
    end

    def run
      if @commit && Book30Entry.exists?
        @io.puts "Refusing to import: book30_entries already holds #{Book30Entry.count} rows. " \
                 "Run `bin/rails book30:rollback COMMIT=1` first if you really want to redo it."
        return nil
      end
      FileUtils.mkdir_p(@out_dir)
      result = nil
      Student.transaction do
        refiled = refile_cm!
        decisions = Classifier.new(lines: @directory.lines, pools: student_pools).run
        creates = decisions.select { |d| Book30Entry::CREATE_OUTCOMES.include?(d.outcome) }
        creates.each { |d| d.student_record = build_placeholder(d) }
        if @commit
          creates.each { |d| d.student_record.save! }
          decisions.each { |d| build_entry(d).save! }
        else
          creates.each do |d|
            next if d.student_record.valid?
            raise "placeholder for #{d.line.cohort} line #{d.line.line_no} is invalid: #{d.student_record.errors.full_messages.join(', ')}"
          end
        end
        write_reports(decisions)
        result = summarize(decisions, refiled)
        raise ActiveRecord::Rollback unless @commit
      end
      result
    end

    private

    # The book's CM01–CM04 (2535–2538) exist in the DB under the bachelor revision 0018 with
    # graduate-school C-prefixed IDs. They belong on the first M.Eng. revision, 0037.
    def refile_cm!
      from = Program.find_by(program_code: CM_REFILE[:from])
      to   = Program.find_by(program_code: CM_REFILE[:to])
      return 0 unless from && to
      scope = Student.where(program: from, admission_year_be: CM_REFILE[:years]).where("student_id LIKE ?", "#{CM_REFILE[:id_prefix]}%")
      moved = scope.to_a # materialise first: the scope stops matching as rows move
      moved.each do |s|
        s.update!(program: to,
                  remark: [ s.remark.presence, "re-filed from #{CM_REFILE[:from]} to #{CM_REFILE[:to]}: first M.Eng. cohorts (book30 #{Date.current})" ].compact.join("; ").truncate(255))
      end
      moved.size
    end

    # { [group_code, year] => [PoolStudent] } for every non-book student.
    def student_pools
      Student.joins(program: :program_group).where.not(source: "book30")
             .pluck("program_groups.code", :admission_year_be, :first_name_th, :last_name_th, :id, :student_id, :study_track)
             .group_by { |g, y, *| [ g, y ] }
             .transform_values do |rows|
               rows.map do |g, y, f, l, id, sid, t|
                 Classifier::PoolStudent.new(id: id, student_id: sid, first: f.to_s, last: l.to_s, group: g, year: y, study_track: t)
               end
             end
    end

    def build_placeholder(d)
      l = d.line
      program, program_note = resolve_program(l.group, l.year)
      d.notes << program_note if program_note
      Student.new(
        student_id: "B30-#{l.cohort}-#{'%03d' % l.line_no}",
        first_name: nil, last_name: nil,
        first_name_th: l.first, last_name_th: l.last,
        admission_year_be: l.year,
        program: program,
        status: "unknown",
        source: "book30",
        sex: l.sex,
        study_track: study_track_for(l),
        remark: "30-year book #{l.cohort} line #{l.line_no}: #{d.note}".truncate(255)
      )
    end

    def study_track_for(l)
      return "special" if l.prefix == "CT"
      return "regular" if l.prefix == "CS" && l.year >= 2533
      nil
    end

    # Latest revision started at or before the admission year; if none, the earliest one.
    # Twins (same start year) → the one with more students admitted that year, then lower code.
    def resolve_program(group_code, year)
      @revisions ||= Program.includes(:program_group).to_a.group_by { |p| p.program_group.code }
      revisions = @revisions[group_code] or raise "no programmes for group #{group_code}"
      eligible = revisions.select { |p| p.year_started_be <= year }
      target_year = eligible.any? ? eligible.map(&:year_started_be).max : revisions.map(&:year_started_be).min
      candidates = (eligible.any? ? eligible : revisions).select { |p| p.year_started_be == target_year }.sort_by(&:program_code)
      notes = []
      notes << "no revision started by #{year}; earliest (#{target_year}) used" if eligible.empty?
      chosen = candidates.first
      if candidates.size > 1
        counts = Student.where(program_id: candidates.map(&:id), admission_year_be: year).group(:program_id).count
        chosen = candidates.max_by { |p| [ counts[p.id] || 0, -p.program_code.to_i ] }
        notes << "revision #{chosen.program_code} chosen among twins #{candidates.map(&:program_code).join('/')}"
      end
      [ chosen, notes.presence&.join("; ") ]
    end

    def build_entry(d)
      l = d.line
      Book30Entry.new(
        cohort: l.cohort, year_be: l.year, line_no: l.line_no, raw_line: l.raw,
        first_name_th: l.first.presence, last_name_th: l.last.presence, alias_name: l.alias_name, sex: l.sex,
        outcome: d.outcome, note: d.note.presence,
        student_id: d.student_record&.id || d.head&.student_record&.id || d.student&.id
      )
    end

    def write_reports(decisions)
      CSV.open(@out_dir.join("decisions.csv"), "w") do |csv|
        csv << %w[cohort year line_no raw_line first_name_th last_name_th sex outcome student_id db_name db_year note]
        decisions.each do |d|
          l = d.line
          target = d.student_record || d.head&.student_record
          sid, name, year = if target then [ target.student_id, target.full_name_th, target.admission_year_be ]
          elsif d.student then [ d.student.student_id, "#{d.student.first} #{d.student.last}", d.student.year ]
          end
          csv << [ l.cohort, l.year, l.line_no, l.raw, l.first, l.last, l.sex, d.outcome, sid, name, year, d.note ]
        end
      end
      CSV.open(@out_dir.join("summary.csv"), "w") do |csv|
        csv << [ "cohort", "year", "book_lines", *Book30Entry::OUTCOMES ]
        decisions.group_by { |d| d.line.cohort }.sort.each do |cohort, ds|
          tally = ds.map(&:outcome).tally
          csv << [ cohort, ds.first.line.year, ds.size, *Book30Entry::OUTCOMES.map { |o| tally[o] || 0 } ]
        end
      end
    end

    def summarize(decisions, refiled)
      outcomes = decisions.map(&:outcome).tally
      creates  = decisions.count { |d| Book30Entry::CREATE_OUTCOMES.include?(d.outcome) }
      @io.puts "#{@commit ? 'COMMITTED' : 'DRY-RUN'}: #{decisions.size} lines, #{creates} placeholders, #{refiled} CM students re-filed -> #{@out_dir}"
      outcomes.sort_by { |_, n| -n }.each { |o, n| @io.puts "  %-26s %5d" % [ o, n ] }
      { lines: decisions.size, outcomes: outcomes, creates: creates, refiled: refiled, out_dir: @out_dir.to_s }
    end
  end
end
