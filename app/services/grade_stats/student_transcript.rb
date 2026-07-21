module GradeStats
  # Per-term transcript for ONE student: every course row (including
  # non-weighted grades like S/U/W — they are part of the record), the term
  # GPA over weighted grades only, and the cumulative GPAX through each term.
  # Chula transcript naming: GPA = semester, GPAX = cumulative.
  class StudentTranscript
    def self.call(student:)
      rows = student.grades.joins(:course)
                    .order(:year_ce, :semester, "courses.course_no")
                    .pluck(:year_ce, :semester, "courses.course_no", "courses.name",
                           "courses.credits", :grade, :grade_weight)

      cum_points = 0.0
      cum_credits = 0.0

      terms = rows.group_by { |r| r[0, 2] }.map do |(year_ce, semester), term_rows|
        courses = term_rows.map do |_, _, course_no, name, credits, grade, _|
          { course_no: course_no, name: name, credits: credits.to_f, grade: grade }
        end

        weighted = term_rows.reject { |r| r[6].nil? }
        points = weighted.sum { |r| r[6].to_f * r[4].to_f }
        credits = weighted.sum { |r| r[4].to_f }
        cum_points += points
        cum_credits += credits

        {
          year_ce: year_ce, semester: semester, courses: courses,
          gpa: credits.zero? ? nil : (points / credits).round(2),
          gpax: cum_credits.zero? ? nil : (cum_points / cum_credits).round(2)
        }
      end

      { terms: terms }
    end
  end
end
