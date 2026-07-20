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
      CSV.generate do |csv|
        csv << header
        @rows.each { |row| csv << row_values(row) }
      end
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
