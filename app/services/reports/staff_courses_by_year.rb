module Reports
  # "Which courses did X teach in a given year?" — by staff initials or name.
  class StaffCoursesByYear < Base
    title    "Courses taught by a staff member in a year"
    section  :courses
    programs :all
    param    :staff, :staff,         required: true   # initials (e.g. NNN) or name
    param    :year,  :academic_year, required: true, label: "Year (B.E.)"   # B.E. year of the offering's term

    def run
      person = find_staff
      cols = [ { key: :course_no, label: "Course No" }, { key: :name, label: "Course" },
               { key: :term, label: "Term" }, { key: :sections, label: "Sections" } ]
      return result(columns: cols, rows: [], summary: "No staff matched '#{staff}'") unless person

      teachings = Teaching.where(staff_id: person.id)
                          .joins(section: { course_offering: [ :course, :semester ] })
                          .where(semesters: { year_be: year })
                          .includes(section: { course_offering: [ :course, :semester ] })

      # One row per course + term: a staff member typically teaches many sections
      # of the same course, which as individual rows would drown the answer.
      # Keyed by course_no so curriculum revisions merge, like the grade reports.
      grouped = teachings.group_by do |t|
        co = t.section.course_offering
        [ co.course.course_no, co.semester ]
      end

      rows = grouped.sort_by { |(course_no, sem), _| [ course_no, sem.semester_number ] }
                    .map do |(course_no, sem), ts|
        { course_no: course_no,
          name: ts.first.section.course_offering.course.name,
          term: sem.display_name,
          sections: ts.map { |t| t.section.section_number }.uniq.sort.join(", ") }
      end

      section_count = teachings.map(&:section_id).uniq.size
      course_count = rows.map { |r| r[:course_no] }.uniq.size
      result(columns: cols, rows: rows,
             summary: "#{course_count} course(s), #{section_count} section(s) taught by #{person.display_name_th} in #{year}")
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
