module Chulabooster
  module Mappers
    class ProgramCourses < Base
      def entity = "program_courses"

      def local_scope = ProgramCourse.includes(:program, :course)

      def local_key(pc)
        [pc.program.program_code.to_s, pc.course.course_no.to_s, pc.course.revision_year_be]
      end

      def cb_key(row)
        course_no, rev_be = Convert.parse_course_id(row["course_id"])
        course_no = row["course_no"].to_s if row["course_no"].present?
        [row["program_id"].to_s, course_no, rev_be]
      end

      # Membership-only: a matched pair has no comparable managed fields locally.
      def comparisons(_pc, _row) = []

      def identifiers(row) = { course_no: row["course_no"], course_group_code: row["course_group_code"] }
    end
  end
end
