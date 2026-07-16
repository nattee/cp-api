module Reports
  # Structured return value for every report. Both the web table renderer and
  # (future) the LINE JSON serializer consume this — never HTML, never prose.
  class Result
    attr_reader :columns, :rows, :summary, :chart, :table_order

    # columns: [{ key: :student_id, label: "Student ID" }, ...]
    # rows:    [{ student_id: "65...", name: "...", ... }, ...]  (keyed by column key)
    # summary: short human sentence, or nil
    # chart:   optional { type:, data:, height: } rendered above the table by
    #          reports/_chart via chart_controller; nil = table only
    # table_order: optional DataTables initial order "colIndex:dir" (e.g.
    #          "0:desc"); nil = DataTables' default (first column ascending)
    def initialize(columns:, rows:, summary: nil, chart: nil, table_order: nil)
      @columns = columns
      @rows = rows
      @summary = summary
      @chart = chart
      @table_order = table_order
    end

    def empty?
      rows.empty?
    end
  end
end
