module Reports
  # Structured return value for every report. Both the web table renderer and
  # (future) the LINE JSON serializer consume this — never HTML, never prose.
  class Result
    attr_reader :columns, :rows, :summary, :chart

    # columns: [{ key: :student_id, label: "Student ID" }, ...]
    # rows:    [{ student_id: "65...", name: "...", ... }, ...]  (keyed by column key)
    # summary: short human sentence, or nil
    # chart:   optional { type:, data:, height: } rendered above the table by
    #          reports/_chart via chart_controller; nil = table only
    def initialize(columns:, rows:, summary: nil, chart: nil)
      @columns = columns
      @rows = rows
      @summary = summary
      @chart = chart
    end

    def empty?
      rows.empty?
    end
  end
end
