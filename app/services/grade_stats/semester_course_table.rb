module GradeStats
  # One row per course (keyed by course_no, revisions merged) in a program
  # group's curriculum that has grades in the given term. Backs the
  # "grade distribution by course" web report.
  class SemesterCourseTable
    def self.call(program_group:, year_ce:, semester:)
      course_nos = Course.joins(program_courses: { program: :program_group })
                         .where(program_groups: { id: program_group.id })
                         .distinct.pluck(:course_no)

      scope = Grade.joins(:course)
                   .where(courses: { course_no: course_nos },
                          year_ce: year_ce, semester: semester)

      counts = scope.where.not(grade: [ nil, "" ]).group("courses.course_no", :grade).count
      gpa_by_no = scope.where.not(grade_weight: nil)
                       .group("courses.course_no")
                       .pluck(Arel.sql("courses.course_no, COUNT(*), " \
                                       "AVG(grades.grade_weight), STDDEV_SAMP(grades.grade_weight)"))
                       .index_by(&:first)

      present_nos = counts.keys.map(&:first).uniq.sort
      # index_by keeps the last occurrence, so ascending revision order means
      # the latest revision's name wins.
      names = Course.where(course_no: present_nos).order(:revision_year_be).index_by(&:course_no)
      grade_columns = Grade::GRADES.select { |g| counts.keys.any? { |_, grade| grade == g } }

      rows = present_nos.map do |no|
        by_grade = Grade::GRADES.each_with_object({}) do |g, h|
          c = counts[[ no, g ]]
          h[g] = c if c
        end
        _, n, avg, sd = gpa_by_no[no]
        {
          course_no: no,
          name: names[no]&.name,
          total: by_grade.values.sum,
          counts: by_grade,
          gpa: { n: n.to_i, mean: avg&.to_f&.round(2), sd: sd&.to_f&.round(2) }
        }
      end

      { grade_columns: grade_columns, rows: rows }
    end
  end
end
