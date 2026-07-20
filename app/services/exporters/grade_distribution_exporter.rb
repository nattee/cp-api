require "csv"

module Exporters
  # Turns the grade-distribution report's rows (GradesController#distribution)
  # into a CSV download. Column order mirrors the on-screen table; GPA and
  # pass-rate are bare numbers (blank when nil) so spreadsheets can sort them.
  class GradeDistributionExporter
    def initialize(rows:, split:)
      @rows = rows
      @split = split
    end

    def to_csv
      csv = CSV.generate do |out|
        out << header
        @rows.each { |row| out << row_values(row) }
      end
      # The header's "% ≥ C" column contains U+2265 (≥). Without a BOM, Excel
      # on a non-UTF-8 locale (Thai-locale Windows, common in this department)
      # reads the file as the legacy locale encoding and mangles that header
      # cell into mojibake. The BOM makes Excel read the file as UTF-8 instead.
      Exporters::Base::BOM + csv
    end

    def filename
      "grade_distribution.csv"
    end

    private

    def header
      cols = %w[Course Title]
      cols << "Term" if @split
      cols + GradesController::LETTER_GRADES + ["W", "Other", "N", "GPA", "% ≥ C"]
    end

    def row_values(row)
      vals = [row[:course_no], row[:title]]
      vals << row[:term] if @split
      vals += (GradesController::LETTER_GRADES + %w[W]).map { |g| row[:buckets][g] }
      vals + [row[:other], row[:n], row[:gpa], row[:pass_rate]]
    end
  end
end
