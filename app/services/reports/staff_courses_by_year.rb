module Reports
  # "Which courses did X teach in a given year?" — by staff initials or name.
  class StaffCoursesByYear < Base
    title    "Courses taught by a staff member in a year"
    section  :courses
    programs :all
    param    :staff, :staff,         required: true   # initials (e.g. NNN) or name
    param    :year,  :academic_year, required: true   # B.E. year of the offering's term

    def run
      person = find_staff
      cols = [ { key: :course_no, label: "Course No" }, { key: :name, label: "Course" },
               { key: :section, label: "Section" }, { key: :term, label: "Term" } ]
      return result(columns: cols, rows: [], summary: "No staff matched '#{staff}'") unless person

      teachings = Teaching.where(staff_id: person.id)
                          .joins(section: { course_offering: [ :course, :semester ] })
                          .where(semesters: { year_be: year })
                          .includes(section: { course_offering: [ :course, :semester ] })

      rows = teachings.map do |t|
        co = t.section.course_offering
        { course_no: co.course.course_no, name: co.course.name,
          section: t.section.section_number, term: co.semester.display_name }
      end.uniq

      result(columns: cols, rows: rows,
             summary: "#{rows.size} course(s) taught by #{person.display_name_th} in #{year}")
    end

    private

    def find_staff
      q = staff.to_s.strip
      if q.match?(/\A[A-Za-z]{2,4}\z/)
        Staff.find_by(initials: q.upcase)
      else
        like = "%#{q}%"
        Staff.where("first_name LIKE :q OR last_name LIKE :q OR " \
                    "first_name_th LIKE :q OR last_name_th LIKE :q", q: like).first
      end
    end
  end
end
