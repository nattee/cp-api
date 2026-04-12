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

    # Attributes that are required but can be derived from other mapped fields.
    # Subclasses override to list attributes that transform_attributes can compute.
    def self.derivable_attributes
      []
    end

    # Convert 0-based column index to Excel-style letter (0 → A, 25 → Z, 26 → AA)
    def self.column_letter(index)
      letter = ""
      i = index
      loop do
        letter = (65 + i % 26).chr + letter
        i = i / 26 - 1
        break if i < 0
      end
      letter
    end

    # Prefix each header with its Excel column letter: ["name", "name"] → ["A: name", "B: name"]
    def self.label_headers(raw_headers)
      raw_headers.each_with_index.map { |h, i| "#{column_letter(i)}: #{h}" }
    end

    # Parse column letter prefix back to 0-based index: "AA" → 26
    def self.column_index_from_letter(letter)
      letter.chars.reduce(0) { |acc, c| acc * 26 + (c.ord - 64) } - 1
    end

    def self.auto_map(raw_headers)
      labeled = label_headers(raw_headers)
      downcased = raw_headers.map { |h| h.to_s.strip.downcase }
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
          mapping[defn[:attribute]] = labeled[match]
        end
      end
    end

    def call
      data_import.update!(state: "processing")

      configs = data_import.sheet_configs.presence || [single_sheet_config]

      total_rows = 0
      total_created = 0
      total_updated = 0
      total_unchanged = 0
      total_skipped = 0
      total_errors = 0
      all_row_errors = []

      with_spreadsheet do |spreadsheet|
        configs.each_with_index do |config, config_idx|
          sheet_name = config["sheet_name"]
          col_mapping = config["column_mapping"] || {}
          constants_raw = config["default_values"] || {}

          spreadsheet.default_sheet = sheet_name if sheet_name.present?

          # Build col_indices from stored column_mapping
          col_indices = {}
          col_mapping.each do |attr_str, labeled_header|
            if labeled_header =~ /\A([A-Z]+): /
              idx = self.class.column_index_from_letter($1)
              col_indices[idx] = attr_str.to_sym
            end
          end

          constants = constants_raw.transform_keys(&:to_sym)

          # Validate required attributes
          mapped_attrs = col_indices.values + constants.keys
          missing = self.class.required_attributes - mapped_attrs - self.class.derivable_attributes
          raise "Required fields not mapped for sheet \"#{sheet_name}\": #{missing.join(', ')}" if missing.any?

          row_errors = []
          created = 0
          updated = 0
          unchanged = 0
          skipped = 0
          total = spreadsheet.last_row - 1

          ActiveRecord::Base.transaction do
            (2..spreadsheet.last_row).each do |row_num|
              row = spreadsheet.row(row_num)
              attrs = extract_attributes(row, col_indices)
              constants.each { |attr, value| attrs[attr] = value }
              attrs = transform_attributes(attrs)

              if attrs.nil?
                skipped += 1
                next
              end

              # Skip rows where any unique key field is blank
              if unique_key_fields.any? && unique_key_fields.any? { |k| attrs[k].blank? }
                skipped += 1
                next
              end

              if data_import.mode == "upsert" && (existing = find_existing_record(attrs))
                existing.assign_attributes(attrs.except(*unique_key_fields))
                if existing.changed?
                  if existing.save
                    updated += 1
                  else
                    row_errors << { row: row_num, sheet: sheet_name, errors: existing.errors.full_messages }
                  end
                else
                  unchanged += 1
                end
              else
                record = build_new_record(attrs)
                if record.save
                  created += 1
                else
                  row_errors << { row: row_num, sheet: sheet_name, errors: record.errors.full_messages }
                end
              end
            end

            if row_errors.any? && !data_import.skip_failures
              raise ActiveRecord::Rollback
            end
          end

          # Store per-sheet results back into config
          config.merge!(
            "total_rows" => total,
            "created_count" => row_errors.any? && !data_import.skip_failures ? 0 : created,
            "updated_count" => row_errors.any? && !data_import.skip_failures ? 0 : updated,
            "unchanged_count" => unchanged,
            "skipped_count" => skipped,
            "error_count" => row_errors.size,
            "row_errors" => row_errors.presence
          )

          total_rows += total
          if row_errors.any? && !data_import.skip_failures
            total_errors += row_errors.size
            all_row_errors.concat(row_errors)
            # Stop processing further sheets on transactional failure
            break
          else
            total_created += created
            total_updated += updated
            total_unchanged += unchanged
            total_skipped += skipped
            total_errors += row_errors.size
            all_row_errors.concat(row_errors)
          end
        end
      end

      if all_row_errors.any? && !data_import.skip_failures
        data_import.update!(
          state: "failed",
          sheet_configs: configs,
          total_rows: total_rows,
          created_count: 0,
          updated_count: 0,
          unchanged_count: total_unchanged,
          skipped_count: total_skipped,
          error_count: total_errors,
          row_errors: all_row_errors
        )
      else
        data_import.update!(
          state: "completed",
          sheet_configs: configs,
          total_rows: total_rows,
          created_count: total_created,
          updated_count: total_updated,
          unchanged_count: total_unchanged,
          skipped_count: total_skipped,
          error_count: total_errors,
          row_errors: all_row_errors.presence
        )
      end
    rescue => e
      data_import.update!(
        state: "failed",
        error_message: e.message
      )
    end

    private

    # Fallback for imports that don't use sheet_configs (legacy single-sheet)
    def single_sheet_config
      {
        "sheet_name" => data_import.sheet_name,
        "column_mapping" => data_import.column_mapping,
        "default_values" => data_import.default_values
      }
    end

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
        # Don't set default_sheet here — each config sets its own sheet
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
