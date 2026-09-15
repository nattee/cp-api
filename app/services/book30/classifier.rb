# app/services/book30/classifier.rb
module Book30
  # Assigns every parsed book line exactly one outcome (Book30Entry::OUTCOMES) against
  # pools of existing students. Pure: no DB access, no writes. Rules and their order:
  # docs/superpowers/specs/2026-09-14-book30-import-design.md § Matching.
  class Classifier
    PoolStudent = Struct.new(:id, :student_id, :first, :last, :group, :year, :study_track, keyword_init: true)

    Decision = Struct.new(:line, :outcome, :student, :kind, :score, :lost, :head, :notes, :student_record, keyword_init: true) do
      def note
        notes.join("; ")
      end
    end

    NEAR_YEAR_WINDOW = 2 # |DB year − book year| within this links as other_year; beyond it is a namesake

    VARIANT_LABELS = { "variant_surname" => "surname", "variant_firstname" => "first name", "variant_typo" => "spelling" }.freeze

    # lines: Array<Directory::Line>; pools: { [group_code, year_be] => Array<PoolStudent> }
    def initialize(lines:, pools:)
      @lines = lines
      @pools = pools
      @all_by_group = Hash.new { |h, k| h[k] = [] }
      pools.each { |(group, _), rows| @all_by_group[group].concat(rows) }
    end

    def run
      decisions = @lines.map { |l| Decision.new(line: l, notes: []) }
      mark_unparsed_and_duplicates(decisions)
      live = decisions.reject(&:outcome)
      find_candidates(live)
      resolve_claims(live)
      mark_second_listings(live)
      mark_creates(live)
      annotate(decisions)
      decisions
    end

    def self.edit_distance(a, b)
      a = a.to_s.chars
      b = b.to_s.chars
      prev = (0..b.size).to_a
      a.each_with_index do |ca, i|
        cur = [ i + 1 ]
        b.each_with_index { |cb, j| cur << [ prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca == cb ? 0 : 1) ].min }
        prev = cur
      end
      prev.last
    end

    private

    def norm(s)   = Directory.normalize(s)
    def lk(f, l)  = Directory.loose_key(f, l)
    def name_key(l) = "#{norm(l.first)} #{norm(l.last)}"
    def dist(a, b) = self.class.edit_distance(a, b)

    def mark_unparsed_and_duplicates(decisions)
      seen = Set.new
      decisions.each do |d|
        l = d.line
        if l.first.blank? || l.last.blank?
          d.outcome = "unparsed"
          next
        end
        key = [ l.cohort, name_key(l) ]
        if seen.include?(key)
          d.outcome = "duplicate_line"
          d.notes << "identical line already in #{l.cohort}"
        else
          seen << key
        end
      end
    end

    # Sets d.student (candidate), d.kind, d.score for every live line that has any candidate.
    def find_candidates(live)
      live.each do |d|
        l = d.line
        pool = @pools[[ l.group, l.year ]] || []
        exact = pool.find { |s| s.first == l.first && s.last == l.last } ||
                pool.find { |s| lk(s.first, s.last) == lk(l.first, l.last) }
        if exact
          d.student, d.kind, d.score = exact, "exact", 0
          next
        end
        nf, nl = norm(l.first), norm(l.last)
        same_first = pool.select { |s| norm(s.first) == nf }
        same_last  = pool.select { |s| norm(s.last) == nl }
        if same_first.size == 1
          s = same_first.first
          d.student, d.kind, d.score = s, "variant_surname", dist(norm(s.last), nl) + 1
        elsif same_last.any?
          s = same_last.min_by { |p| dist(norm(p.first), nf) }
          d.student, d.kind, d.score = s, "variant_firstname", dist(norm(s.first), nf) + 1
        elsif (best = pool.map { |s| [ dist(norm(s.first) + norm(s.last), nf + nl), s ] }.min_by(&:first)) && best[0] <= 2
          d.student, d.kind, d.score = best[1], "variant_typo", best[0] + 1
        else
          others = @all_by_group[l.group].reject { |s| s.year == l.year }
          matches = others.select { |s| lk(s.first, s.last) == lk(l.first, l.last) }
          if (xy = matches.min_by { |s| (s.year - l.year).abs })
            d.student, d.kind, d.score = xy, year_kind(xy, l), 1
          elsif (b2 = others.map { |s| [ dist(norm(s.first) + norm(s.last), nf + nl), s ] }
                       .min_by { |cand_dist, s| [ cand_dist, (s.year - l.year).abs ] }) && b2[0] <= 1
            d.student, d.kind, d.score = b2[1], year_kind(b2[1], l), 2
          end
        end
      end
    end

    def year_kind(student, line)
      (student.year - line.year).abs <= NEAR_YEAR_WINDOW ? "other_year" : "namesake"
    end

    # One DB student may be claimed by several lines: exact beats near, lower score wins,
    # ties go to the earlier cohort then the earlier line. Losers stay unlinked (d.lost).
    def resolve_claims(live)
      live.select { |d| d.student && d.kind != "namesake" }.group_by { |d| d.student.id }.each_value do |claims|
        winner = claims.min_by { |d| [ d.score, d.line.year, d.line.cohort, d.line.line_no ] }
        winner.outcome = case winner.kind
        when "exact"      then "linked_exact"
        when "other_year" then "linked_other_year"
        else                   "linked_variant"
        end
        winner.notes << "book differs in #{VARIANT_LABELS[winner.kind]}" if VARIANT_LABELS.key?(winner.kind)
        winner.notes << "book year #{winner.line.year}, DB year #{winner.student.year}" if winner.kind == "other_year"
        if (conflict = track_conflict(winner.line.prefix, winner.student.study_track))
          winner.notes << conflict
        end
        (claims - [ winner ]).each { |d| d.lost = true }
      end
    end

    def mark_second_listings(live)
      by_key = live.group_by { |d| [ d.line.group, name_key(d.line) ] }
      live.select { |d| d.outcome.nil? }.each do |d|
        other = by_key[[ d.line.group, name_key(d.line) ]].find { |o| !o.equal?(d) && o.outcome.to_s.start_with?("linked") }
        next unless other
        lost_student_id = d.student&.student_id
        d.outcome = "second_listing"
        d.student = other.student
        d.notes << "same person linked under #{other.line.cohort}"
        d.notes << "lost claim on #{lost_student_id} to a closer name" if d.lost
      end
    end

    # The earliest remaining listing of a name (per DB group) creates; later ones are
    # second listings pointing at that head line (the importer wires the created student).
    def mark_creates(live)
      live.select { |d| d.outcome.nil? }.group_by { |d| [ d.line.group, name_key(d.line) ] }.each_value do |listings|
        listings = listings.sort_by { |d| [ d.line.year, d.line.cohort, d.line.line_no ] }
        head = listings.first
        head.outcome =
          if head.student && head.kind == "namesake"
            head.notes << "only DB match #{head.student.student_id} entered #{head.student.year}, #{(head.student.year - head.line.year).abs} years away"
            "create_namesake"
          elsif head.student && head.lost
            head.notes << "candidate #{head.student.student_id} #{head.student.first} #{head.student.last} taken by a closer book name"
            "create_lost_claim"
          elsif (@pools[[ head.line.group, head.line.year ]] || []).empty?
            "create_book_only_cohort"
          else
            "create_missing"
          end
        head.student = nil
        listings.drop(1).each do |d|
          d.outcome = "second_listing"
          d.student = nil
          d.head = head
          d.notes << "same person, student record created under #{head.line.cohort}"
        end
      end
    end

    def annotate(decisions)
      by_key = decisions.group_by { |d| name_key(d.line) }
      decisions.each do |d|
        next if d.outcome == "unparsed"
        others = by_key[name_key(d.line)].reject { |o| o.line.group == d.line.group }.map { |o| o.line.cohort }.uniq
        d.notes << "also listed under #{others.join(', ')} (other programme)" if others.any?
        d.notes << "maiden/alias in book: #{d.line.alias_name}" if d.line.alias_name.present?
      end
    end

    def track_conflict(prefix, study_track)
      return "book says CT but study_track=regular" if prefix == "CT" && study_track == "regular"
      return "book says CS (regular) but study_track=special" if prefix == "CS" && study_track == "special"
      nil
    end
  end
end
