module Chulabooster
  module Mappers
    class Programs < Base
      def entity = "programs"
      def local_scope = Program.includes(:program_group)
      def local_key(p) = p.program_code
      def cb_key(row) = row["program_id"].to_s

      def comparisons(p, row)
        [
          [:name_en, p.name_en, row["program_name"], true],
          [:name_th, p.name_th, row["program_name_alt"], true],
          [:year_started, p.year_started, Convert.ce_to_be(row["revision_year"]), true],
          [:alternative_program_code, p.alternative_program_code, row["program_code"], true]
        ]
      end

      def identifiers(row) = { program_name: row["program_name"], revision_year: row["revision_year"] }
    end
  end
end
