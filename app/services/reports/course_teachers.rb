module Reports
  # "Who teaches this subject?" — instructors of a course's sections in a term.
  class CourseTeachers < Base
    title    "Who teaches this subject"
    section  :courses
    programs :all
    param    :course_no, :course,          required: true
    param    :semester,  :semester_record               # optional; defaults to latest

    def run
      sem = semester_scope
      offerings = CourseOffering.joins(:course)
                                .where(courses: { course_no: course_no })
      offerings = offerings.where(semester_id: sem.id) if sem
      offerings = offerings.includes(:course, :semester, sections: { teachings: :staff })

      rows = []
      offerings.each do |off|
        off.sections.each do |sec|
          sec.teachings.each do |t|
            rows << { course_no: off.course.course_no, name: off.course.name,
                      section: sec.section_number, instructor: t.staff.display_name_th,
                      term: off.semester.display_name }
          end
        end
      end

      result(
        columns: [ { key: :course_no, label: "Course No" }, { key: :name, label: "Course" },
                   { key: :section, label: "Section" }, { key: :instructor, label: "Instructor" },
                   { key: :term, label: "Term" } ],
        rows: rows,
        summary: "#{rows.size} teaching assignment(s) for #{course_no}#{" in #{sem.display_name}" if sem}"
      )
    end
  end
end
