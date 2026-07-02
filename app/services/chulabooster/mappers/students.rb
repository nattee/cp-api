module Chulabooster
  module Mappers
    class Students < Base
      def entity = "students"
      def local_scope = Student.all
      def local_key(s) = s.student_id.to_s
      def cb_key(row) = row["student_id"].to_s

      def comparisons(s, row)
        [
          [:first_name,       s.first_name,       row["firstname"],      true],
          [:last_name,        s.last_name,        row["lastname"],       true],
          [:first_name_th,    s.first_name_th,    row["firstname_alt"],  true],
          [:last_name_th,     s.last_name_th,     row["lastname_alt"],   true],
          [:sex,              s.sex,              row["gender"],         true],
          [:admission_year_be, s.admission_year_be, Convert.ce_to_be(row["start_academic_year"]), true],
          [:status,           s.status,           row["student_status"], false]  # encoding-unverified
        ]
      end

      def identifiers(row) = { firstname: row["firstname"], lastname: row["lastname"] }
    end
  end
end
