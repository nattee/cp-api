require "csv"
require "cgi"
require "open3"

# Reconciles the 30th-anniversary book's alumni directory (ทำเนียบศิษย์เก่า,
# PDF pages 232–303 of the 2006 volume) against the students table and emits
# CSV reports — REPORT ONLY, writes nothing to the database.
#
# The extraction pipeline was validated 2026-08-19..20 (97–100% name match in
# well-covered cohorts): mutool structured text → Thai PUA glyph-variant
# decoding (PSL fonts encode repositioned tone marks as U+F700–F71A) →
# combining-mark reorder (visual → logical) → two-column layout split →
# "รุ่น <CODE>" generation headers.
#
# Requires `mutool` (mupdf-tools) on PATH. Run via `bin/rails book30:report`.
class Book30Reconciler
  DIRECTORY_PAGES = (232..303)  # this PDF edition; AJ/AS staff sections are skipped

  # Thai PUA glyph-variant → standard codepoint (PSL/UPC OpenType convention)
  PUA = {
    0xF700 => "ฐ", 0xF701 => "ิ", 0xF702 => "ี", 0xF703 => "ึ", 0xF704 => "ื",
    0xF705 => "่", 0xF706 => "้", 0xF707 => "๊", 0xF708 => "๋", 0xF709 => "์",
    0xF70A => "่", 0xF70B => "้", 0xF70C => "๊", 0xF70D => "๋", 0xF70E => "์",
    0xF70F => "ญ", 0xF710 => "ั", 0xF711 => "ํ", 0xF712 => "็",
    0xF713 => "่", 0xF714 => "้", 0xF715 => "๊", 0xF716 => "๋", 0xF717 => "ํ",
    0xF718 => "ุ", 0xF719 => "ู", 0xF71A => "ฺ"
  }.freeze
  CLUSTER_VOWELS = "ิีึืุูัฺ"
  CLUSTER_TONES  = "่้๊๋์ํ็"

  # Generation epochs: gen N = epoch + N - 1 (B.E.). CT is the CS special
  # program (ภาคนอกเวลาราชการ) — its students live in the CS group.
  EPOCHS = { "CP" => 2517, "CM" => 2535, "CS" => 2514, "CD" => 2541, "SE" => 2545, "CT" => 2533 }.freeze
  GEN_TO_GROUP = { "CT" => "CS" }.freeze # everything else maps to its own code

  TITLE_RE = /\A(?:(?:ศ|รศ|ผศ|อ|ดร|นพ|พญ|ทพ|พล\.?[อทร]\.?[อทตร]?|พ\.?[ตอ]\.?[อทต]?|ร\.?[ตทอ]|น\.?[ตทอ]|จ\.?[สอ]|ส\.?[ตอ])\.\s*|(?:อาจารย์|นาย|นางสาว|นาง|น\.ส\.|นส\.|ว่าที่\s*ร\.?ต\.?(?:หญิง)?|พ\.ท\.ญ\.|คุณ|ร้อยตรี|ร้อยโท|ร้อยเอก|เรืออากาศ\S*|พันตำรวจ\S*|พลตำรวจ\S*|นาวา\S*)\s+)+/
  NOISE_RE = /\A(\d+|C ?P ?CHULA.*|.*30th ANNIVERSARY.*|CHUL.*|\* เพื่อป้องกัน.*|.*cuca@cp\.eng\.chula\.ac\.th.*|ทำเนียบ.*)\z/
  HEADER_RE = /\Aรุ่น ?([A-Z]+[0-9]*)\z/

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
    xml, status = Open3.capture2("mutool", "draw", "-q", "-F", "stext", "-o", "-",
                                 @pdf_path, "#{DIRECTORY_PAGES.first}-#{DIRECTORY_PAGES.last}")
    raise "mutool failed (#{status.exitstatus}) — is mupdf-tools installed?" unless status.success?

    sequence = []
    xml.split(/<page id="page\d+"/).drop(1).each do |chunk|
      lines = chunk.scan(%r{<line bbox="([\d.]+) ([\d.]+) [\d.]+ [\d.]+"[^>]*>(.*?)</line>}m).filter_map do |x0, y0, body|
        text = decode(body.scan(/<char[^>]*c="([^"]*)"/).join).squish
        [ x0.to_f, y0.to_f, text ] unless text.blank? || text.match?(NOISE_RE)
      end
      # Two-column layout: left column (x < 180) reads before right. mutool
      # emits lines in BLOCK order, not top-down, so each column must be
      # re-sorted by y or generation headers scramble against their names.
      [ true, false ].each do |left|
        lines.select { |x0, _, _| (x0 < 180) == left }
             .sort_by { |_, y0, _| y0 }
             .each { |_, _, text| sequence << text }
      end
    end

    groups = Hash.new { |h, k| h[k] = [] }
    current = nil
    sequence.each do |text|
      if (m = text.match(HEADER_RE))
        current = m[1]
        groups[current] # materialize even if the section turns out empty
      elsif current
        groups[current] << text
      end
    end
    groups
  end

  def decode(raw)
    # Entity-only char runs scan out as US-ASCII substrings, and
    # CGI.unescapeHTML refuses to emit non-ASCII into an ASCII string —
    # re-encode to UTF-8 first or every Thai entity survives untouched.
    text = CGI.unescapeHTML(raw.encode(Encoding::UTF_8)).each_char.map { |c| PUA[c.ord] || c }.join
    # reorder combining marks visual → logical: vowels before tone marks
    out = +""
    cluster = +""
    flush = lambda do
      next if cluster.empty?
      out << cluster.each_char.select { |c| CLUSTER_VOWELS.include?(c) }.join \
          << cluster.each_char.select { |c| CLUSTER_TONES.include?(c) }.join
      cluster.clear
    end
    text.each_char do |c|
      if CLUSTER_VOWELS.include?(c) || CLUSTER_TONES.include?(c)
        cluster << c
      else
        flush.call
        out << c
      end
    end
    flush.call
    out
  end

  def clean_name(line)
    stripped = line.gsub(/\([^)]*\)/, " ").squish.sub(TITLE_RE, "").strip
    parts = stripped.split
    [ parts.first, parts.drop(1).join(" ") ]
  end

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

  def normalize(name)
    name.to_s.gsub(/[#{CLUSTER_TONES}]/o, "").gsub(/\s/, "")
  end

  def loose_key(first, last)
    "#{normalize(first)}|#{normalize(last)}"
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
