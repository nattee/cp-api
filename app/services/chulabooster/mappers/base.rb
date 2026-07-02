module Chulabooster
  module Mappers
    class Base
      # Subclasses implement: entity, local_scope, local_key, cb_key, comparisons, identifiers.

      def field_diffs(local_rec, cb_row)
        comparisons(local_rec, cb_row).filter_map do |field, local_val, cb_val, verified|
          next if Convert.norm(local_val) == Convert.norm(cb_val)
          { field: field.to_s, local: local_val, cb: cb_val, verified: verified }
        end
      end

      # Default: no extra display columns for CB-only rows beyond the key.
      def identifiers(_cb_row) = {}
    end
  end
end
