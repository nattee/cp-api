module Reports
  # "How many thesis credits has each student enrolled?" — master programs only.
  class ThesisCredits < Base
    title    "Thesis credits per student"
    section  :thesis
    programs [ :CM, :CS, :SE ]                       # master groups only
    param    :admission_year, :academic_year, label: "Admission year (B.E.)"  # optional cohort filter

    def run
      thesis_credits = Grade.graded.joins(:course)
                            .where(courses: { is_thesis: true })
                            .group(:student_id).sum(:credits_grant)

      students = Student.where(id: thesis_credits.keys)
      students = students.where(admission_year_be: admission_year) if admission_year.present?

      rows = students.map do |s|
        { student_id: s.student_id, name: s.display_name,
          thesis_credits: thesis_credits[s.id] || 0 }
      end.sort_by { |r| -r[:thesis_credits] }

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :thesis_credits, label: "Thesis Credits" } ],
        rows: rows,
        summary: "#{rows.size} student(s) with thesis credits"
      )
    end
  end
end
