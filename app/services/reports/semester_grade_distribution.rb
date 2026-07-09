module Reports
  # "How did each course do this semester?" — one row per course (course_no,
  # revisions merged) with grade counts and course GPA, for one program group.
  class SemesterGradeDistribution < Base
    title    "Grade distribution by course"
    section  :courses
    programs :all
    param    :program_group, :program_group, required: true
    param    :year,          :academic_year, required: true, label: "Year (B.E.)"   # B.E. year of the grades
    param    :term,          :term,          required: true

    def run
      group = ProgramGroup.find_by(code: program_group)
      return result(columns: fixed_columns, rows: [], summary: "Unknown program group.") unless group

      # Grades store the academic year in C.E. (Grade#year_ce); input is B.E.
      data = GradeStats::SemesterCourseTable.call(
        program_group: group, year_ce: year.to_i - 543, semester: term.to_i
      )

      grade_cols = data[:grade_columns].map { |g| { key: grade_key(g), label: g } }
      columns = fixed_columns.insert(3, *grade_cols)

      rows = data[:rows].map do |r|
        row = { course_no: r[:course_no], name: r[:name], total: r[:total],
                gpa: r[:gpa][:mean], sd: r[:gpa][:sd] }
        data[:grade_columns].each { |g| row[grade_key(g)] = r[:counts][g] }
        row
      end

      result(
        columns: columns,
        rows: rows,
        summary: "#{rows.size} course(s) with grades in #{year}/#{term} (#{group.code})",
        chart: chart_data(data)
      )
    end

    private

    def fixed_columns
      [ { key: :course_no, label: "Course No" }, { key: :name, label: "Name" },
        { key: :total, label: "N" },
        { key: :gpa, label: "GPA" }, { key: :sd, label: "SD" } ]
    end

    # "B+" -> :g_bp — flat row keys for the generic table/CSV renderers.
    def grade_key(grade)
      :"g_#{grade.downcase.tr('+', 'p')}"
    end

    def chart_data(data)
      return nil if data[:rows].empty?
      {
        type: "horizontal-stacked-bar",
        height: [ data[:rows].size * 24 + 80, 240 ].max,
        data: {
          labels: data[:rows].map { |r| r[:course_no] },
          colorBy: "grade",
          datasets: data[:grade_columns].map do |g|
            { code: g, data: data[:rows].map { |r| r[:counts][g] || 0 } }
          end
        }
      }
    end
  end
end
