require "csv"

module Chulabooster
  class ReportWriter
    def initialize(run_dir)
      @run_dir = run_dir
      FileUtils.mkdir_p(@run_dir)
    end

    def seen_path(entity) = File.join(@run_dir, "#{entity}_seen.tsv")

    def append_changed(entity, rows)  # rows: [{ key:, diffs: [{field,local,cb,verified}] }]
      append_csv("#{entity}_changed.csv", %w[key field local cb verified]) do |csv|
        rows.each do |r|
          r[:diffs].each { |d| csv << [r[:key].inspect, d[:field], d[:local], d[:cb], d[:verified]] }
        end
      end
    end

    def append_cb_only(entity, rows)  # rows: [{ key:, identifiers: {} }]
      cols = %w[key] + (rows.first&.dig(:identifiers)&.keys&.map(&:to_s) || [])
      append_csv("#{entity}_cb_only.csv", cols) do |csv|
        rows.each { |r| csv << [r[:key].inspect, *r[:identifiers].values] }
      end
    end

    def append_local_only(entity, keys)
      append_csv("#{entity}_local_only.csv", %w[key]) { |csv| keys.each { |k| csv << [k.inspect] } }
    end

    def write_summary(counts)  # counts: array of the per-entity hashes
      table = summary_table(counts)
      File.write(File.join(@run_dir, "summary.md"),
                 "# ChulaBooster reconciliation\n\n```\n#{table}\n```\n\nReport dir: #{@run_dir}\n")
      table
    end

    private

    def append_csv(name, header)
      path = File.join(@run_dir, name)
      write_header = !File.exist?(path)
      CSV.open(path, "a") do |csv|
        csv << header if write_header
        yield csv
      end
    end

    def summary_table(counts)
      head = %w[entity local cb matched identical changed cb-only local-only]
      rows = counts.map do |c|
        [c[:entity], c[:local], c[:cb], c[:matched], c[:identical], c[:changed], c[:cb_only], c[:local_only]]
      end
      widths = head.each_index.map { |i| ([head[i]] + rows.map { |r| r[i].to_s }).map(&:length).max }
      fmt = ->(r) { r.each_with_index.map { |v, i| v.to_s.ljust(widths[i]) }.join("  ") }
      ([fmt.call(head)] + rows.map { |r| fmt.call(r) }).join("\n")
    end
  end
end
