module GradeStats
  # Per-term GPS (term GPA) and GPAX (cumulative GPA) aggregates for one
  # admission cohort of a program group. Computed in Ruby from a single pluck:
  # a cohort is a few hundred students, and per-term cumulative GPA is trivial
  # here but painful in MySQL.
  class CohortGpa
    def self.call(program_group:, admission_year_be:)
      student_ids = Student.joins(program: :program_group)
                           .where(program_groups: { id: program_group.id },
                                  students: { admission_year_be: admission_year_be })
                           .pluck(:id)

      rows = Grade.joins(:course)
                  .where(student_id: student_ids)
                  .where.not(grade_weight: nil)
                  .pluck(:student_id, :year_ce, :semester, :grade_weight, "courses.credits")

      by_term = rows.group_by { |_, y, s, _, _| [ y, s ] }
      # Running per-student totals across terms, for GPAX.
      cumulative = Hash.new { |h, k| h[k] = { points: 0.0, credits: 0.0 } }

      terms = by_term.keys.sort.map do |year_ce, semester|
        per_student = by_term[[ year_ce, semester ]].group_by(&:first)

        gps_values = per_student.filter_map do |_, grades|
          gpa_of(points(grades), credits(grades))
        end

        per_student.each do |sid, grades|
          cumulative[sid][:points]  += points(grades)
          cumulative[sid][:credits] += credits(grades)
        end

        gpax_values = cumulative.values.filter_map { |t| gpa_of(t[:points], t[:credits]) }

        { year_ce: year_ce, semester: semester,
          gps: Stats.aggregate(gps_values), gpax: Stats.aggregate(gpax_values) }
      end

      { terms: terms }
    end

    def self.points(grades)
      grades.sum { |_, _, _, w, c| w.to_f * c.to_f }
    end
    private_class_method :points

    def self.credits(grades)
      grades.sum { |_, _, _, _, c| c.to_f }
    end
    private_class_method :credits

    def self.gpa_of(points, credits)
      credits.zero? ? nil : points / credits
    end
    private_class_method :gpa_of
  end
end
