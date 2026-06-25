module Reports
  # Structured return value for every report. Both the web table renderer and
  # (future) the LINE JSON serializer consume this — never HTML, never prose.
  class Result
    attr_reader :columns, :rows, :summary

    # columns: [{ key: :student_id, label: "Student ID" }, ...]
    # rows:    [{ student_id: "65...", name: "...", ... }, ...]  (keyed by column key)
    # summary: short human sentence, or nil
    def initialize(columns:, rows:, summary: nil)
      @columns = columns
      @rows = rows
      @summary = summary
    end

    def empty?
      rows.empty?
    end
  end
end
