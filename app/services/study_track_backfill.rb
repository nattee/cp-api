require "csv"

# Backfills students.study_track ("regular"/"special") for the M.Sc.-CS
# track split (ภาคนอกเวลาราชการ — the department's "CT" cohorts) from three
# independent evidence sources, validated against each other and against the
# 30th-anniversary book's CT rosters before this was written; see
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md.
#
# Dry-run unless commit:. Never overwrites an already-set study_track (a
# changed verdict lands in review.csv instead), so re-runs are idempotent.
class StudyTrackBackfill
  SPECIAL_LABEL = "โครงการภาคนอกเวลาราชการ"
  SPECIAL_FEES = %w[4 04 07].freeze
  REGULAR_FEES = %w[1 01].freeze
  # CB fee_type + project partition the CS group exactly in these years.
  CB_RULE_YEARS = (2533..2553)
  # From 2554 fees blur (the regular program went special-fee too), but the
  # university kept issuing the 71xx ID range for special admissions
  # through the last special intake in 2560.
  SEGMENT_RULE_YEARS = (2554..2560)

  Decision = Struct.new(:track, :evidence, :review_reason)

  def initialize(cb_rows:, commit: false, out_dir: Rails.root.join("tmp", "study_track_backfill"), io: $stdout)
    @cb_rows = cb_rows
    @commit = commit
    @out_dir = Pathname(out_dir)
    @io = io
  end

  def run
    FileUtils.mkdir_p(@out_dir)
    assigned_counts = Hash.new(0)
    assignments = []
    reviews = []

    Student.includes(program: :program_group).order(:admission_year_be, :student_id).each do |student|
      decision = decide(student, @cb_rows[student.student_id])

      if student.study_track.present?
        if decision.track && decision.track != student.study_track
          reviews << [ student, "already #{student.study_track}, evidence now says #{decision.track} (#{decision.evidence})" ]
        end
        next
      end

      if decision.review_reason
        reviews << [ student, decision.review_reason ]
      elsif decision.track
        assignments << [ student, decision ]
        assigned_counts[[ group_code(student), decision.track ]] += 1
        student.update!(study_track: decision.track) if @commit
      end
    end

    write_csv("assignments.csv", %w[student_id name group year track evidence],
              assignments.map { |s, d| [ s.student_id, s.display_name, group_code(s), s.admission_year_be, d.track, d.evidence ] })
    write_csv("review.csv", %w[student_id name group year enrollment_method reason],
              reviews.map { |s, r| [ s.student_id, s.display_name, group_code(s), s.admission_year_be, s.enrollment_method, r ] })

    @io.puts "#{@commit ? 'COMMITTED' : 'DRY-RUN'}: #{assignments.size} assignments, #{reviews.size} review rows -> #{@out_dir}"
    assigned_counts.sort.each { |(group, track), n| @io.puts "  #{group} #{track}: #{n}" }
    { assignments: assignments.size, reviews: reviews.size }
  end

  # Pure classification for one student. Rule order (spec): dept label ->
  # CB fee/project (CS 2533-2553) -> ID segment (CS 2554-2560) -> regular
  # for CS <= 2532 (predates the special program) -> nil (out of scope).
  # A label-vs-classifier disagreement is a tripwire: no assignment, review.
  def decide(student, cb_row)
    labeled = student.enrollment_method.to_s.strip == SPECIAL_LABEL
    cs = group_code(student) == "CS"
    year = student.admission_year_be

    classifier, evidence, why_unclassified =
      if cs && CB_RULE_YEARS.cover?(year)
        track = cb_classify(cb_row)
        [ track,
          ("cb:project=#{cb_row&.dig('project')},fee=#{cb_row&.dig('fee_type')}" if track),
          (cb_row.nil? ? "CS #{year}: not in CB export" : "CS #{year}: unrecognized CB combo project=#{cb_row['project']} fee=#{cb_row['fee_type']}") ]
      elsif cs && SEGMENT_RULE_YEARS.cover?(year)
        track = segment_classify(student.student_id)
        [ track,
          ("segment:#{student.student_id[2, 2]}" if track),
          "CS #{year}: unrecognized ID segment #{student.student_id[2, 2]}" ]
      else
        [ nil, nil, nil ]
      end

    if labeled && classifier == "regular"
      Decision.new(nil, nil, "label says special but classifier says regular (#{evidence})")
    elsif labeled
      Decision.new("special", "label:enrollment_method")
    elsif classifier
      Decision.new(classifier, evidence)
    elsif cs && year <= 2532
      Decision.new("regular", "pre-special-era")
    elsif why_unclassified
      Decision.new(nil, nil, why_unclassified)
    else
      Decision.new(nil, nil, nil)
    end
  end

  private

  def group_code(student)
    student.program&.program_group&.code
  end

  def cb_classify(cb_row)
    return nil unless cb_row
    project = cb_row["project"].to_s
    fee = cb_row["fee_type"].to_s
    return "special" if project == "212" && SPECIAL_FEES.include?(fee)
    return "regular" if project == "201" && REGULAR_FEES.include?(fee)
    nil
  end

  def segment_classify(student_id)
    return nil unless student_id.to_s.length == 10
    { "71" => "special", "70" => "regular" }[student_id[2, 2]]
  end

  def write_csv(name, headers, rows)
    CSV.open(@out_dir.join(name), "w") do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end
end
