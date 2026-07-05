require "json"
require "fileutils"

module Chulabooster
  # Dumps raw CB export rows to disk as JSON Lines (one row per line, per entity), so
  # reconciliation and ad hoc analysis can run offline against a local cache instead of
  # re-hitting CB every time. Resumable per-entity via checkpoint.json, mirroring
  # Reconciler's checkpoint convention (the student_courses pull alone takes tens of minutes).
  class Snapshotter
    def initialize(client:, dir:)
      @client = client
      @dir = dir
      FileUtils.mkdir_p(@dir)
    end

    def done?(entity) = File.exist?(done_path(entity))

    def resume_cursor(entity)
      return nil unless File.exist?(checkpoint_path)
      cp = JSON.parse(File.read(checkpoint_path), symbolize_names: true)
      cp[:entity] == entity ? cp[:next_cursor] : nil
    end

    def dump_entity(entity, start_cursor: nil)
      path = File.join(@dir, "#{entity}.jsonl")
      File.write(path, "") unless start_cursor || File.exist?(path)
      count = File.exist?(path) ? File.foreach(path).count : 0

      @client.each_page(entity, start_cursor: start_cursor) do |rows, next_cursor|
        File.open(path, "a") { |f| rows.each { |r| f.puts(JSON.generate(r)) } }
        count += rows.size
        write_checkpoint(entity, next_cursor, count)
      end

      FileUtils.touch(done_path(entity))
      count
    end

    private

    def done_path(entity) = File.join(@dir, "#{entity}.done")
    def checkpoint_path = File.join(@dir, "checkpoint.json")

    def write_checkpoint(entity, next_cursor, count)
      File.write(checkpoint_path, JSON.pretty_generate(entity: entity, next_cursor: next_cursor, count: count))
    end
  end
end
