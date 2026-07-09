module Reports
  # "Who hasn't earned enough credits in this course group?" — threshold typed
  # by staff for v1 (CurriculumRequirement model is a follow-on spec).
  class GroupCreditShortfall < Base
    title    "Who lacks enough credits in a course group"
    section  :curriculum
    programs :all
    param    :course_group,     :course_group,  required: true
    param    :required_credits, :integer,       required: true
    param    :admission_year,   :academic_year, label: "Admission year (B.E.)"  # optional cohort filter

    def run
      threshold = required_credits.to_i

      students = Student.all
      students = students.where(admission_year_be: admission_year) if admission_year.present?

      # earned credits per student within the group (SUM ignores NULL credits_grant)
      earned = Grade.graded.joins(:course)
                    .where(courses: { course_group: course_group })
                    .group(:student_id).sum(:credits_grant)

      rows = students.filter_map do |s|
        got = earned[s.id] || 0
        next if got >= threshold
        { student_id: s.student_id, name: s.display_name, earned: got,
          required: threshold, missing: threshold - got }
      end.sort_by { |r| -r[:missing] }

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :earned, label: "Earned" }, { key: :required, label: "Required" },
                   { key: :missing, label: "Missing" } ],
        rows: rows,
        summary: "#{rows.size} student(s) below #{threshold} credits in '#{course_group}'"
      )
    end
  end
end
