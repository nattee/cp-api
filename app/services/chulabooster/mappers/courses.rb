module Chulabooster
  module Mappers
    class Courses < Base
      def entity = "courses"
      def local_scope = Course.all
      def local_key(c) = [c.course_no.to_s, c.revision_year]
      def cb_key(row) = [row["course_no"].to_s, Convert.ce_to_be(row["revision_year"])]

      def comparisons(c, row)
        [
          [:name,      c.name,      row["course_name"],     true],
          [:name_th,   c.name_th,   row["course_name_alt"], true],
          [:credits,   c.credits,   Convert.int_or_nil(row["credits"]),   true],
          [:l_credits, c.l_credits, Convert.int_or_nil(row["l_credits"]), true],
          [:l_hours,   c.l_hours,   Convert.int_or_nil(row["l_hours"]),   true],
          [:nl_hours,  c.nl_hours,  Convert.int_or_nil(row["nl_hours"]),  true],
          [:s_hours,   c.s_hours,   Convert.int_or_nil(row["s_hours"]),   true],
          [:is_thesis, c.is_thesis, Convert.bool(row["is_thesis"]), true],
          [:is_gened,  c.is_gened,  Convert.bool(row["gened"]),     true]
        ]
      end

      def identifiers(row) = { course_name: row["course_name"] }
    end
  end
end
