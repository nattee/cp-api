require "open3"
require "cgi"

module Book30
  # The alumni directory of the 30-year book (ทำเนียบศิษย์เก่า, PDF pages 232–303) as
  # cohorts of printed lines. Extraction pipeline validated 2026-08-19..20 (97–100% name
  # match in well-covered cohorts): mutool structured text → PUA glyph-variant decode →
  # combining-mark reorder → two-column split at x≈180 → `รุ่น <CODE>` headers.
  class Directory
    DEFAULT_PDF = "/home/dae/book ครบรอบ 30 ปี.pdf".freeze
    DIRECTORY_PAGES = (232..303) # this PDF edition; AJ/AS staff sections are skipped

    # Thai PUA glyph-variant → standard codepoint (PSL/UPC OpenType convention).
    # Copied verbatim from Book30Reconciler::PUA (validated 2026-08-19..20).
    PUA = {
      0xF700 => "ฐ", 0xF701 => "ิ", 0xF702 => "ี", 0xF703 => "ึ", 0xF704 => "ื",
      0xF705 => "่", 0xF706 => "้", 0xF707 => "๊", 0xF708 => "๋", 0xF709 => "์",
      0xF70A => "่", 0xF70B => "้", 0xF70C => "๊", 0xF70D => "๋", 0xF70E => "์",
      0xF70F => "ญ", 0xF710 => "ั", 0xF711 => "ํ", 0xF712 => "็",
      0xF713 => "่", 0xF714 => "้", 0xF715 => "๊", 0xF716 => "๋", 0xF717 => "ํ",
      0xF718 => "ุ", 0xF719 => "ู", 0xF71A => "ฺ"
    }.freeze
    CLUSTER_VOWELS = "ิีึืุูัฺ".freeze
    CLUSTER_TONES  = "่้๊๋์ํ็".freeze

    # Cohort epochs from the book's own legend (p. 231): generation N enrolled in
    # epoch + N − 1 (B.E.). CT is the CS evening programme — same DB group as CS.
    EPOCHS = { "CE" => 2512, "CS" => 2514, "CP" => 2517, "CT" => 2533, "CM" => 2535, "CD" => 2541, "SE" => 2545 }.freeze
    GEN_TO_GROUP = { "CT" => "CS" }.freeze
    SKIP_PREFIXES = %w[AJ AS].freeze # faculty / staff sections — not students

    TITLE_RE = /\A(?:(?:ศ|รศ|ผศ|อ|ดร|นพ|พญ|ทพ|พล\.?[อทร]\.?[อทตร]?|พ\.?[ตอ]\.?[อทต]?|ร\.?[ตทอ]|น\.?[ตทอ]|จ\.?[สอ]|ส\.?[ตอ])\.\s*|(?:อาจารย์|นาย|นางสาว|นาง|น\.ส\.|นส\.|ว่าที่\s*ร\.?ต\.?(?:หญิง)?|พ\.ท\.ญ\.|คุณ|ร้อยตรี|ร้อยโท|ร้อยเอก|เรืออากาศ\S*|พันตำรวจ\S*|พลตำรวจ\S*|นาวา\S*)\s+)+/
    NOISE_RE  = /\A(\d+|C ?P ?CHULA.*|.*30th ANNIVERSARY.*|CHUL.*|\* เพื่อป้องกัน.*|.*cuca@cp\.eng\.chula\.ac\.th.*|ทำเนียบ.*)\z/
    HEADER_RE = /\Aรุ่น ?([A-Z]+[0-9]*)\z/
    FEMALE_TITLE_RE = /\A(?:นางสาว|นาง|น\.ส\.|นส\.|ว่าที่\s*ร\.?ต\.?\s*หญิง|พ\.ท\.ญ\.)/
    MALE_TITLE_RE   = /\A(?:นาย|ว่าที่\s*ร\.?ต\.?(?!\s*หญิง))/

    Line = Struct.new(:cohort, :prefix, :group, :year, :line_no, :raw, :first, :last, :alias_name, :sex, keyword_init: true)

    def self.from_pdf(pdf_path = DEFAULT_PDF, pages: DIRECTORY_PAGES)
      raise ArgumentError, "PDF not found: #{pdf_path}" unless File.exist?(pdf_path.to_s)
      xml, status = Open3.capture2("mutool", "draw", "-q", "-F", "stext", "-o", "-",
                                   pdf_path.to_s, "#{pages.first}-#{pages.last}")
      raise "mutool failed (#{status.exitstatus}) — is mupdf-tools installed?" unless status.success?
      new(xml)
    end

    # For hosts without mutool: read structured text that was extracted elsewhere with
    # `mutool draw -q -F stext -o <file> <pdf> 232-303`.
    def self.from_stext_file(path)
      raise ArgumentError, "stext file not found: #{path}" unless File.exist?(path.to_s)
      new(File.read(path.to_s, encoding: "UTF-8"))
    end

    def initialize(stext_xml)
      @xml = stext_xml
    end

    # { "CP14" => ["นาย ...", ...], ... } in reading order. Headers with no names still appear.
    def cohorts
      @cohorts ||= begin
        sequence = []
        @xml.split(/<page id="page\d+"/).drop(1).each do |chunk|
          lines = chunk.scan(%r{<line bbox="([\d.]+) ([\d.]+) [\d.]+ [\d.]+"[^>]*>(.*?)</line>}m).filter_map do |x0, y0, body|
            text = self.class.decode(body.scan(/<char[^>]*c="([^"]*)"/).join).squish
            [ x0.to_f, y0.to_f, text ] unless text.blank? || text.match?(NOISE_RE)
          end
          # Two-column layout: left column (x < 180) reads before right. mutool emits lines in
          # BLOCK order, not top-down, so each column is re-sorted by y or headers scramble.
          [ true, false ].each do |left|
            lines.select { |x0, _, _| (x0 < 180) == left }.sort_by { |_, y0, _| y0 }.each { |_, _, text| sequence << text }
          end
        end
        groups = Hash.new { |h, k| h[k] = [] }
        current = nil
        sequence.each do |text|
          if (m = text.match(HEADER_RE))
            current = m[1]
            groups[current]
          elsif current
            groups[current] << text
          end
        end
        groups
      end
    end

    # Student lines with cohort facts and parsed names. A bracket-only line is folded into the
    # previous line's alias_name (the book prints a maiden name on its own line a few times).
    def lines
      @lines ||= cohorts.sort.flat_map do |cohort, texts|
        prefix, number = cohort.match(/\A([A-Z]+)(\d*)\z/).captures
        next [] if SKIP_PREFIXES.include?(prefix) || EPOCHS[prefix].nil? || number.blank?
        year  = EPOCHS[prefix] + number.to_i - 1
        group = GEN_TO_GROUP.fetch(prefix, prefix)
        out = []
        texts.each do |raw|
          if (m = raw.match(/\A\(([^)]*)\)\z/)) && out.any?
            out.last.alias_name ||= m[1].strip
            next
          end
          first, last = self.class.clean_name(raw)
          out << Line.new(cohort: cohort, prefix: prefix, group: group, year: year, line_no: out.size + 1, raw: raw,
                          first: first, last: last, alias_name: raw[/\(([^)]*)\)/, 1]&.strip,
                          sex: self.class.sex_from_title(raw))
        end
        out
      end
    end

    def self.decode(raw)
      # Entity-only char runs scan out as US-ASCII substrings, and CGI.unescapeHTML refuses to
      # emit non-ASCII into an ASCII string — re-encode to UTF-8 first.
      text = CGI.unescapeHTML(raw.encode(Encoding::UTF_8)).each_char.map { |c| PUA[c.ord] || c }.join
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

    # "นาย สมชาย (แซ่ลี้) ใจดี" → ["สมชาย", "ใจดี"]; a one-word line → ["เอนก", ""]
    def self.clean_name(raw)
      stripped = raw.gsub(/\([^)]*\)/, " ").squish.sub(TITLE_RE, "").strip
      parts = stripped.split
      [ parts.first.to_s, parts.drop(1).join(" ") ]
    end

    def self.normalize(name)
      name.to_s.gsub(/[#{CLUSTER_TONES}]/o, "").gsub(/\s/, "")
    end

    def self.loose_key(first, last)
      "#{normalize(first)}|#{normalize(last)}"
    end

    def self.sex_from_title(raw)
      return "F" if raw.match?(FEMALE_TITLE_RE)
      return "M" if raw.match?(MALE_TITLE_RE)
      nil
    end
  end
end
