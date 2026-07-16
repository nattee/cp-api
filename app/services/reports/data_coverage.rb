module Reports
  # "Which terms are missing data" — per-term coverage matrix (data presence,
  # NOT import-run audit: data_imports rows don't know which term a file
  # covered, and data also arrives via scraper and ChulaBooster sync).
  # One row per term (union of Semester records and grade terms), one column
  # per dataset, era-aware red/yellow flags so a missed term stands out.
  # Design: docs/superpowers/specs/2026-07-16-data-coverage-report-design.md
  class DataCoverage < Base
    title    "Which terms are missing data"
    section  :admin
    programs :all
    param    :program_courses_only, :boolean, label: "Program courses only"

    MISSING_CLASS = "report-cell-missing".freeze
    LOW_CLASS     = "report-cell-low".freeze
    LOW_RATIO     = 0.5          # yellow when below this fraction of the peer median
    BLANK         = "—".freeze   # predates the dataset / not applicable

    # Count columns that get era + red/yellow treatment. :ungraded is
    # deliberately absent — zero ungraded is GOOD, so it is informational
    # only (it just goes BLANK alongside :grades outside the grades era).
    FLAGGED_KEYS = %i[new_students grades offerings sections time_slots].freeze

    def run
      terms  = collect_terms
      counts = build_counts
      rows   = terms.map { |t| build_row(t, counts) }
      apply_flags!(rows, terms)
      # newest term first — the whole point is checking the recent terms
      result(columns: columns_spec, rows: rows, summary: summary_text(rows), table_order: "0:desc")
    end

    private

    def columns_spec
      [
        { key: :term,         label: "Term" },
        { key: :new_students, label: "New Students", class_key: :new_students_class },
        { key: :grades,       label: "Grades",       class_key: :grades_class },
        { key: :ungraded,     label: "Ungraded" },
        { key: :offerings,    label: "Offerings",    class_key: :offerings_class },
        { key: :sections,     label: "Sections",     class_key: :sections_class },
        { key: :time_slots,   label: "Time Slots",   class_key: :time_slots_class }
      ]
    end

    # Every term that has a Semester record or any grade, newest first,
    # as [year_be, semester_number] pairs. Summer terms appear naturally.
    def collect_terms
      semester_terms = Semester.pluck(:year_be, :semester_number)
      grade_terms = Grade.distinct.pluck(:year_ce, :semester)
                         .map { |year_ce, sem| [year_ce + 543, sem] }
      (semester_terms + grade_terms).uniq.sort.reverse
    end

    def program_courses_only?
      program_courses_only == "1"
    end

    # One grouped count per dataset, keyed [year_be, semester_number].
    def build_counts
      curriculum = ProgramCourse.select(:course_id)
      grades    = Grade.all
      offerings = CourseOffering.joins(:semester)
      sections  = Section.joins(course_offering: :semester)
      slots     = TimeSlot.joins(section: { course_offering: :semester })
      if program_courses_only?
        grades    = grades.where(course_id: curriculum)
        offerings = offerings.where(course_id: curriculum)
        sections  = sections.where(course_offerings: { course_id: curriculum })
        slots     = slots.where(course_offerings: { course_id: curriculum })
      end
      to_be = ->(h) { h.transform_keys { |(year_ce, sem)| [year_ce + 543, sem] } }
      sem_group = ["semesters.year_be", "semesters.semester_number"]
      {
        new_students: Student.group(:admission_year_be).count,
        grades:       to_be.(grades.group(:year_ce, :semester).count),
        ungraded:     to_be.(grades.where(grade: nil).group(:year_ce, :semester).count),
        offerings:    offerings.group(*sem_group).count,
        sections:     sections.group(*sem_group).count,
        time_slots:   slots.group(*sem_group).count
      }
    end

    def build_row(term, counts)
      year_be, sem = term
      {
        term:         "#{year_be}/#{sem}",
        # cohorts arrive in semester 1; other semesters are not applicable
        new_students: sem == 1 ? counts[:new_students].fetch(year_be, 0) : BLANK,
        grades:       counts[:grades].fetch(term, 0),
        ungraded:     counts[:ungraded].fetch(term, 0),
        offerings:    counts[:offerings].fetch(term, 0),
        sections:     counts[:sections].fetch(term, 0),
        time_slots:   counts[:time_slots].fetch(term, 0)
      }
    end

    # Era rule + flags, in place. A dataset's era starts at its earliest
    # non-zero term; before that the dataset simply wasn't tracked, so the
    # cell is BLANK, not red. Within the era: 0 -> red; below LOW_RATIO of
    # the median of non-zero same-semester-number counts in OTHER years ->
    # yellow (summers compare only with summers).
    def apply_flags!(rows, terms)
      FLAGGED_KEYS.each { |key| flag_column!(key, rows, terms) }
      # :ungraded is a sub-count of :grades — blank it outside the grades era.
      rows.each { |row| row[:ungraded] = BLANK if row[:grades] == BLANK }
    end

    def flag_column!(key, rows, terms)
      applicable = rows.each_index.select { |i| rows[i][key] != BLANK }
      era_start = applicable.select { |i| rows[i][key].positive? }
                            .map { |i| terms[i] }.min
      if era_start.nil? # dataset has no data at all: nothing is "missing"
        applicable.each { |i| rows[i][key] = BLANK }
        return
      end
      in_era, pre_era = applicable.partition { |i| (terms[i] <=> era_start) >= 0 }
      pre_era.each { |i| rows[i][key] = BLANK }
      in_era.each do |i|
        value = rows[i][key]
        if value.zero?
          rows[i][:"#{key}_class"] = MISSING_CLASS
          next
        end
        peers = in_era.select do |j|
          j != i && terms[j][1] == terms[i][1] && rows[j][key].positive?
        end
        peer_median = median(peers.map { |j| rows[j][key] })
        rows[i][:"#{key}_class"] = LOW_CLASS if peer_median && value < LOW_RATIO * peer_median
      end
    end

    def median(values)
      return nil if values.empty?
      sorted = values.sort
      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Legend sentence + the curriculum diagnostic: a program revision with no
    # program_courses rows means a curriculum arrived but its courses were
    # never imported/linked. The "0000" placeholder program is exempt.
    def summary_text(rows)
      parts = ["Coverage for #{rows.size} term(s). " \
               "Red = missing, yellow = low vs. same-semester median, — = predates the dataset."]
      unlinked = Program.where.missing(:program_courses).includes(:program_group)
                        .reject(&:placeholder?)
                        .sort_by { |p| [-p.year_started_be, p.program_code] }
      if unlinked.any?
        labels = unlinked.map { |p| "#{p.program_group.code} #{p.year_started_be} (#{p.program_code})" }
        parts << "⚠ Programs with no courses linked: #{labels.join(', ')}."
      end
      parts.join(" ")
    end
  end
end
