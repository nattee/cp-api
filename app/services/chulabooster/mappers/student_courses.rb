module Chulabooster
  module Mappers
    class StudentCourses < Base
      def entity = "student_courses"

      def local_scope = Grade.includes(:student, :course)

      # NOTE: refinement of the spec's listed key — `section` is dropped. The local grade unique index
      # is (student_id, course_id, year_ce, semester); section is not part of local grade identity and most
      # imported grades have a nil section, so including it would cause spurious mismatches.
      #
      # NOTE (fixed after a live run against real ChulaBooster data returned matched: 0 across all
      # 31,079 local / 49,502 CB rows): Grade#year_ce is Gregorian/CE (confirmed real range 2018..2025),
      # NOT Buddhist Era like course.revision_year_be / admission_year_be — hence the column is named
      # _ce, and CB's already-CE academic_year must NOT be converted to BE here. And CB's semester_code
      # is a string like "s1"/"s2"/"s3", not a plain integer like local's Grade#semester —
      # Convert.semester_number strips the "s" prefix.
      def local_key(g)
        [
          g.student.student_id.to_s,
          g.course.course_no.to_s,
          g.course.revision_year_be,
          g.year_ce,
          g.semester
        ]
      end

      def cb_key(row)
        course_no, rev_be = Convert.parse_course_id(row["course_id"])
        [
          row["student_id"].to_s,
          course_no,
          rev_be,
          Convert.int_or_nil(row["academic_year"]),
          Convert.semester_number(row["semester_code"])
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
