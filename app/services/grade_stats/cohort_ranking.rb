module GradeStats
  # Top students of one admission cohort ranked by GPAX (cumulative weighted
  # GPA over all graded terms). SQL-side aggregation, 2-decimal rounding like
  # the other GradeStats services. Ties broken by total credits (desc).
  class CohortRanking
    def self.call(program_group:, admission_year_be:, limit: 5)
      rows = Student.joins(program: :program_group)
                    .where(program_groups: { id: program_group.id },
                           students: { admission_year_be: admission_year_be })
                    .joins(grades: :course)
                    .where.not(grades: { grade_weight: nil })
                    .group("students.id")
                    .having("SUM(courses.credits) > 0")
                    .order(Arel.sql(
                      "SUM(grades.grade_weight * courses.credits) / SUM(courses.credits) DESC, " \
                      "SUM(courses.credits) DESC, students.id ASC"))
                    .limit(limit)
                    .pluck(Arel.sql(
                      "students.id, " \
                      "SUM(grades.grade_weight * courses.credits) / SUM(courses.credits), " \
                      "SUM(courses.credits)"))

      students = Student.where(id: rows.map(&:first)).index_by(&:id)
      rows.each_with_index.map do |(id, gpax, credits), index|
        student = students[id]
        { rank: index + 1, student_id: student.student_id, name: student.display_name,
          status: student.status, gpax: gpax.to_f.round(2), credits: credits.to_f.round(1) }
      end
    end
  end
end
