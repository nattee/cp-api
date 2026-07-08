module GradeStats
  # Grade distribution + course GPA for one course in one term — or one result
  # per term of the year when semester is nil (used by the LINE tool when the
  # user doesn't name a term). Aggregates by course_no: all curriculum
  # revisions of the course count together.
  # See docs/superpowers/specs/2026-07-08-grade-reports-design.md.
  class CourseDistribution
    def self.call(course_no:, year_ce:, semester: nil)
      return term_result(course_no, year_ce, semester) if semester

      base_scope(course_no, year_ce).distinct.pluck(:semester).sort
                                    .map { |s| term_result(course_no, year_ce, s) }
    end

    def self.term_result(course_no, year_ce, semester)
      scope = base_scope(course_no, year_ce).where(semester: semester)

      raw = scope.where.not(grade: [ nil, "" ]).group(:grade).count
      counts = Grade::GRADES.each_with_object({}) { |g, h| h[g] = raw[g] if raw[g] }
      weights = scope.where.not(grade_weight: nil).pluck(:grade_weight).map(&:to_f)

      {
        course_no: course_no,
        year_ce: year_ce,
        semester: semester,
        total: counts.values.sum,
        counts: counts,
        gpa: { n: weights.size, mean: Stats.mean(weights), sd: Stats.sample_sd(weights) }
      }
    end
    private_class_method :term_result

    def self.base_scope(course_no, year_ce)
      Grade.joins(:course).where(courses: { course_no: course_no }, year_ce: year_ce)
    end
    private_class_method :base_scope
  end
end
