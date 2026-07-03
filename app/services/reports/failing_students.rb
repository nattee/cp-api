module Reports
  # "Which students failed this subject?" — grade F in a course for a term.
  class FailingStudents < Base
    title    "Which students failed this subject"
    section  :courses
    programs :all
    param    :course_no, :course,        required: true
    param    :year,      :academic_year, required: true   # B.E. year of the grade
    param    :term,      :term                            # optional 1/2/3

    def run
      scope = Grade.graded.joins(:course, :student)
                   .where(courses: { course_no: course_no }, grade: "F", year_ce: year)
      scope = scope.where(semester: term) if term.present?

      rows = scope.map do |g|
        { student_id: g.student.student_id, name: g.student.display_name,
          term: "#{g.year_ce}/#{g.semester}", grade: g.grade }
      end

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :term, label: "Term" }, { key: :grade, label: "Grade" } ],
        rows: rows,
        summary: "#{rows.size} student(s) failed #{course_no} in #{year}"
      )
    end
  end
end
