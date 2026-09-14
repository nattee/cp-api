require "csv"

# Reconciles the 30th-anniversary book's alumni directory (ทำเนียบศิษย์เก่า,
# PDF pages 232–303 of the 2006 volume) against the students table and emits
# CSV reports — REPORT ONLY, writes nothing to the database.
#
# PDF extraction (mutool → PUA decode → mark reorder → column split → cohort
# headers) lives in Book30::Directory, shared with the importer. This class
# only does matching against the students table.
#
# Requires `mutool` (mupdf-tools) on PATH. Run via `bin/rails book30:report`.
class Book30Reconciler
  EPOCHS = Book30::Directory::EPOCHS
  GEN_TO_GROUP = Book30::Directory::GEN_TO_GROUP

  def initialize(pdf_path:, out_dir: Rails.root.join("tmp", "book30_report"), io: $stdout)
    @pdf_path = pdf_path
    @out_dir = Pathname(out_dir)
    @io = io
  end

  def run
    FileUtils.mkdir_p(@out_dir)
    groups = parse_directory
    pools = student_pools

    confirmed, discrepancies, book_only, db_only, summary = [], [], [], [], []
    used = Set.new                      # global — CT and CS gens of one year share a pool
    pool_gens = Hash.new { |h, k| h[k] = [] }

    groups.sort.each do |gen, lines|
      prefix, number = gen.match(/\A([A-Z]+)(\d*)\z/).captures
      next if %w[AJ AS].include?(prefix) # faculty/staff sections — not students

      epoch = EPOCHS[prefix]
      year = epoch && number.present? ? epoch + number.to_i - 1 : nil
      group = GEN_TO_GROUP.fetch(prefix, prefix)
      pool = year ? (pools[[ group, year ]] || []) : []
      pool_gens[[ group, year ]] << gen if year

      exact = pool.index_by { |s| "#{s[:first]} #{s[:last]}" }
      loose = pool.index_by { |s| loose_key(s[:first], s[:last]) }
      by_first = pool.group_by { |s| normalize(s[:first]) }
      counts = Hash.new(0)

      lines.each do |line|
        first, last = clean_name(line)
        next if first.blank?

        if (s = exact["#{first} #{last}"]) || (s = loose[loose_key(first, last)])
          tier = exact.key?("#{first} #{last}") ? "exact" : "tone_insensitive"
          used << s[:sid]
          counts[:confirmed] += 1
          confirmed << [ gen, year, line, s[:sid], "#{s[:first]} #{s[:last]}", tier,
                         s[:study_track], track_conflict(prefix, s[:study_track]) ]
        elsif (cands = by_first[normalize(first)]) && cands.size == 1
          s = cands.first
          used << s[:sid]
          counts[:discrepancy] += 1
          discrepancies << [ gen, year, line, s[:sid], s[:first], s[:last], s[:study_track] ]
        else
          counts[:book_only] += 1
          book_only << [ gen, year, line ]
        end
      end

      summary << [ gen, year, lines.size, pool.size, counts[:confirmed],
                   counts[:discrepancy], counts[:book_only] ]
    end

    # db-only pass runs once per pool, after every generation has claimed its
    # matches — a CS-group student unmatched by both the CS and CT rosters of
    # their year appears exactly once.
    pool_gens.keys.uniq.sort_by(&:to_s).each do |(group, year)|
      (pools[[ group, year ]] || []).reject { |s| used.include?(s[:sid]) }.each do |s|
        db_only << [ group, year, pool_gens[[ group, year ]].join("+"), s[:sid],
                     "#{s[:first]} #{s[:last]}", s[:study_track], s[:status] ]
      end
    end

    write_csv("confirmed.csv", %w[gen year book_line student_id db_name tier study_track note], confirmed)
    write_csv("name_discrepancies.csv", %w[gen year book_line student_id db_first db_last study_track], discrepancies)
    write_csv("book_only.csv", %w[gen year book_line], book_only)
    write_csv("db_only.csv", %w[group year book_gens student_id db_name study_track status], db_only)
    write_csv("summary.csv", %w[gen year book_names db_students confirmed name_discrepancies book_only], summary)

    totals = summary.each_with_object(Hash.new(0)) do |row, t|
      %i[book db confirmed discrepancy book_only].each_with_index { |k, i| t[k] += row[i + 2].to_i }
    end
    @io.puts "book30 report -> #{@out_dir}"
    @io.puts "  generations: #{summary.size} (AJ/AS staff sections skipped)"
    @io.puts "  book names: #{totals[:book]}"
    @io.puts "  confirmed: #{totals[:confirmed]}  name discrepancies: #{totals[:discrepancy]}"
    @io.puts "  book-only: #{totals[:book_only]} (incl. #{groups.keys.count { |g| g.start_with?('CE') }} CE generations — program unidentified)"
    @io.puts "  db-only (once per student): #{db_only.size}"
    totals.merge(db_only: db_only.size)
  end

  private

  # --- PDF extraction ---

  def parse_directory
    Book30::Directory.from_pdf(@pdf_path).cohorts
  end

  def clean_name(line)  = Book30::Directory.clean_name(line)
  def normalize(name)   = Book30::Directory.normalize(name)
  def loose_key(f, l)   = Book30::Directory.loose_key(f, l)

  # --- matching ---

  def student_pools
    Student.joins(program: :program_group)
           .pluck("program_groups.code", :admission_year_be, :first_name_th, :last_name_th,
                  :student_id, :status, :study_track)
           .group_by { |code, year, *| [ code, year ] }
           .transform_values do |rows|
             rows.map do |_, _, first, last, sid, status, track|
               { first: first.to_s, last: last.to_s, sid: sid, status: status, study_track: track }
             end
           end
  end

  def track_conflict(prefix, study_track)
    return "book says CT but study_track=regular" if prefix == "CT" && study_track == "regular"
    return "book says CS (regular) but study_track=special" if prefix == "CS" && study_track == "special"
    nil
  end

  def write_csv(name, headers, rows)
    CSV.open(@out_dir.join(name), "w") do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end
end
