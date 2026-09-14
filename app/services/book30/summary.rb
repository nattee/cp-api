module Book30
  # Numbers for the admin page /data_sources/book30, computed live from book30_entries
  # and students. "DB" per cohort = non-book students in that programme group and
  # admission year (CS and CT split by study track); "DB only" = those no entry links to.
  class Summary
    Row = Struct.new(:cohort, :year, :prefix, :book, :db, :counts, :db_only, keyword_init: true)

    def any?
      Book30Entry.exists?
    end

    def outcome_counts
      @outcome_counts ||= Book30Entry.group(:outcome).count
    end

    def totals
      oc = outcome_counts
      {
        lines: oc.values.sum,
        links: Book30Entry::LINK_OUTCOMES.sum { |o| oc[o] || 0 },
        creates: Book30Entry::CREATE_OUTCOMES.sum { |o| oc[o] || 0 },
        ignored: Book30Entry::IGNORE_OUTCOMES.sum { |o| oc[o] || 0 },
        placeholders: Student.where(source: "book30").count
      }
    end

    # One representative entry per outcome (earliest cohort, then line).
    def examples
      @examples ||= Book30Entry::OUTCOMES.to_h do |o|
        [ o, Book30Entry.includes(:student).where(outcome: o).order(:cohort, :line_no).first ]
      end.compact
    end

    def cohort_rows
      @cohort_rows ||= begin
        entry_counts = Book30Entry.group(:cohort, :year_be, :outcome).count
        linked_ids = Book30Entry.where.not(student_id: nil).where(outcome: Book30Entry::LINK_OUTCOMES + [ "second_listing" ]).distinct.pluck(:student_id).to_set
        db = Student.joins(program: :program_group).where.not(source: "book30")
                    .pluck("program_groups.code", :admission_year_be, :study_track, :id)
        db_by_cohort = Hash.new { |h, k| h[k] = [] }
        db.each do |group, year, track, id|
          prefix = group == "CS" && year >= Directory::EPOCHS["CT"] ? (track == "special" ? "CT" : "CS") : group
          next unless Directory::EPOCHS[prefix]
          db_by_cohort["%s%02d" % [ prefix, year - Directory::EPOCHS[prefix] + 1 ]] << id
        end
        entry_counts.keys.map { |c, y, _| [ c, y ] }.uniq.map do |cohort, year|
          counts = Book30Entry::OUTCOMES.to_h { |o| [ o, entry_counts[[ cohort, year, o ]] || 0 ] }
          ids = db_by_cohort[cohort]
          Row.new(cohort: cohort, year: year, prefix: cohort[0, 2], book: counts.values.sum, db: ids.size,
                  counts: counts, db_only: ids.count { |id| !linked_ids.include?(id) })
        end.sort_by { |r| [ Directory::EPOCHS.keys.index(r.prefix) || 99, r.year, r.cohort ] }
      end
    end

    # { "CE" => [rows...], "CS" => [...], ... } in legend order.
    def group_rows
      cohort_rows.group_by(&:prefix)
    end

    def db_not_in_book_total
      cohort_rows.sum(&:db_only)
    end

    def group_totals(rows)
      Row.new(cohort: "total", year: nil, prefix: rows.first&.prefix, book: rows.sum(&:book), db: rows.sum(&:db),
              counts: Book30Entry::OUTCOMES.to_h { |o| [ o, rows.sum { |r| r.counts[o] } ] }, db_only: rows.sum(&:db_only))
    end
  end
end
