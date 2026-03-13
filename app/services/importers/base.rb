module Importers
  class Base
    attr_reader :data_import

    def initialize(data_import)
      @data_import = data_import
    end

    # Subclasses must implement this (replaces column_mapping + required_headers):
    # Returns array of hashes:
    #   { attribute: :symbol, label: "Human Name", required: bool, aliases: ["alias1", ...] }
    def self.attribute_definitions
      raise NotImplementedError
    end

    def self.required_attributes
      attribute_definitions.select { |d| d[:required] }.map { |d| d[:attribute] }
    end

    def self.attribute_labels
      attribute_definitions.each_with_object({}) { |d, h| h[d[:attribute]] = d[:label] }
    end

    def self.auto_map(file_headers)
      normalized = file_headers.map { |h| h.to_s.strip }
      downcased = normalized.map(&:downcase)
      claimed = Set.new

      attribute_definitions.each_with_object({}) do |defn, mapping|
        match = nil
        (defn[:aliases] || []).each do |ali|
          target = ali.strip.downcase
          downcased.each_with_index do |h, i|
            next if claimed.include?(i)
            if h == target
              match = i
              break
            end
          end
          break if match
        end

        if match
          claimed.add(match)
          mapping[defn[:attribute]] = normalized[match]
        end
      end
    end

    def call
      data_import.update!(state: "processing")

      with_spreadsheet do |spreadsheet|
        # Build col_indices from stored column_mapping
        headers = spreadsheet.row(1).map { |h| h.to_s.strip }
        col_indices = {}
        data_import.column_mapping.each do |attr_str, header_str|
          idx = headers.index { |h| h == header_str }
          col_indices[idx] = attr_str.to_sym if idx
        end

        # Build constant values hash (symbol keys)
        constants = (data_import.default_values || {}).transform_keys(&:to_sym)

        # Validate required attributes are present (via column mapping or constants)
        mapped_attrs = col_indices.values + constants.keys
        missing = self.class.required_attributes - mapped_attrs
        raise "Required fields not mapped: #{missing.join(', ')}" if missing.any?

        row_errors = []
        created = 0
        updated = 0
        total = spreadsheet.last_row - 1 # exclude header

        ActiveRecord::Base.transaction do
          (2..spreadsheet.last_row).each do |row_num|
            row = spreadsheet.row(row_num)
            attrs = extract_attributes(row, col_indices)
            constants.each { |attr, value| attrs[attr] = value }
            attrs = transform_attributes(attrs)

            if data_import.mode == "upsert" && (existing = find_existing_record(attrs))
              existing.assign_attributes(attrs.except(*unique_key_fields))
              if existing.changed?
                if existing.save
                  updated += 1
                else
                  row_errors << { row: row_num, errors: existing.errors.full_messages }
                end
              end
            else
              record = build_new_record(attrs)
              if record.save
                created += 1
              else
                row_errors << { row: row_num, errors: record.errors.full_messages }
              end
            end
          end

          if row_errors.any?
            raise ActiveRecord::Rollback
          end
        end

        if row_errors.any?
          data_import.update!(
            state: "failed",
            total_rows: total,
            created_count: 0,
            updated_count: 0,
            error_count: row_errors.size,
            row_errors: row_errors
          )
        else
          data_import.update!(
            state: "completed",
            total_rows: total,
            created_count: created,
            updated_count: updated,
            error_count: 0
          )
        end
      end
    rescue => e
      data_import.update!(
        state: "failed",
        error_message: e.message
      )
    end

    private

    def with_spreadsheet(&block)
      data_import.file.open do |tempfile|
        spreadsheet = case File.extname(data_import.file.filename.to_s).downcase
        when ".xlsx"
          Roo::Excelx.new(tempfile.path)
        when ".xls"
          Roo::Excel.new(tempfile.path)
        when ".csv"
          Roo::CSV.new(tempfile.path)
        else
          raise "Unsupported file format. Please upload .xlsx, .xls, or .csv"
        end
        spreadsheet.default_sheet = data_import.sheet_name if data_import.sheet_name.present?
        block.call(spreadsheet)
      end
    end

    def extract_attributes(row, col_indices)
      attrs = {}
      col_indices.each do |idx, attr_sym|
        value = row[idx]
        attrs[attr_sym] = value.is_a?(String) ? value.strip : value
      end
      attrs
    end

    # Subclasses must implement:
    def find_existing_record(_attrs)
      raise NotImplementedError
    end

    def build_new_record(_attrs)
      raise NotImplementedError
    end

    def transform_attributes(attrs)
      attrs
    end

    def unique_key_fields
      []
    end
  end
end
