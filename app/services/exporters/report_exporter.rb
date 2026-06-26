require "csv"

module Exporters
  # Turns any Reports::Result into a CSV download (columns -> header row).
  class ReportExporter
    def initialize(result, filename: "report")
      @result = result
      @name = filename
    end

    def to_csv
      CSV.generate do |csv|
        csv << @result.columns.map { |c| c[:label] }
        @result.rows.each { |row| csv << @result.columns.map { |c| row[c[:key]] } }
      end
    end

    def filename
      "#{@name}.csv"
    end
  end
end
