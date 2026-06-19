require "csv"
require "caxlsx"

module Exporters
  # Shared base for tabular exporters. Subclasses define `HEADERS` (an array of
  # column titles) and a private `rows` method returning an array of row arrays.
  #
  # Two output formats are available:
  #   - CSV  via #to_csv  (with an optional UTF-8 BOM, see #byte_order_mark?)
  #   - XLSX via #to_xlsx (real Excel — preserves text-typed cells)
  #
  # Controllers should use the generic trio #data / #content_type / #filename,
  # which dispatch on the subclass's #xlsx? hook. (The schedule exporter still
  # calls #to_csv directly, so that path is kept stable.)
  class Base
    BOM = "﻿".freeze

    XLSX_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
    CSV_CONTENT_TYPE = "text/csv".freeze

    # Binary/string payload for the chosen format.
    def data
      xlsx? ? to_xlsx : to_csv
    end

    def content_type
      xlsx? ? XLSX_CONTENT_TYPE : CSV_CONTENT_TYPE
    end

    def to_csv
      csv = CSV.generate do |out|
        out << headers
        rows.each { |row| out << row }
      end
      byte_order_mark? ? BOM + csv : csv
    end

    def to_xlsx
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: worksheet_name) do |sheet|
        sheet.add_row(headers)
        # `column_types` lets a subclass pin specific columns to a cell type.
        # This matters for all-digit string columns (e.g. student_id): left to
        # auto-inference, Axlsx casts "5970136421" to a number and Excel shows
        # scientific notation. Forcing :string keeps it as text. A nil entry
        # (or nil array) means auto-infer that column.
        types = column_types
        rows.each { |row| sheet.add_row(row, types: types) }
      end
      package.to_stream.read
    end

    def filename
      raise NotImplementedError, "#{self.class} must implement #filename"
    end

    private

    # Override to true to export XLSX instead of CSV.
    def xlsx?
      false
    end

    # Worksheet tab name for XLSX exports.
    def worksheet_name
      "Export"
    end

    # Per-column Axlsx cell types for XLSX (e.g. [:string, nil, :integer]).
    # nil means auto-infer every column.
    def column_types
      nil
    end

    # Override to true for CSV exports opened directly in Excel that may
    # contain non-ASCII (e.g. Thai) text. A UTF-8 BOM makes Excel read the file
    # as UTF-8 instead of the legacy locale encoding, which otherwise mangles
    # Thai characters. Leave false for CSV that round-trips back through an
    # importer — a BOM on the header row corrupts column-name matching.
    # Irrelevant for XLSX (always UTF-8).
    def byte_order_mark?
      false
    end

    def headers
      self.class::HEADERS
    end

    def rows
      raise NotImplementedError, "#{self.class} must implement #rows"
    end
  end
end
