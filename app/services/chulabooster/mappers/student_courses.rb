module Chulabooster
  module Mappers
    class StudentCourses < Base
      def entity = "student_courses"

      def local_scope = Grade.includes(:student, :course)

      # NOTE: refinement of the spec's listed key — `section` is dropped. The local grade unique index
      # is (student_id, course_id, year, semester); section is not part of local grade identity and most
      # imported grades have a nil section, so including it would cause spurious mismatches.
      def local_key(g)
        [
          g.student.student_id.to_s,
          g.course.course_no.to_s,
          g.course.revision_year,
          g.year,
          Convert.norm(g.semester)
        ]
      end

      def cb_key(row)
        course_no, rev_be = Convert.parse_course_id(row["course_id"])
        [
          row["student_id"].to_s,
          course_no,
          rev_be,
          Convert.ce_to_be(row["academic_year"]),
          Convert.norm(row["semester_code"])  # encoding-unverified key part
        ]
      end

      def comparisons(g, row)
        [
          [:grade,         g.grade,         row["grade"],         true],
          [:credits_grant, g.credits_grant, Convert.int_or_nil(row["credits_grant"]), true]
        ]
      end

      def identifiers(row) = { course_id: row["course_id"], academic_year: row["academic_year"] }
    end
  end
end
