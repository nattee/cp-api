require "json"

module Chulabooster
  class Reconciler
    def initialize(client:, writer:, run_dir:)
      @client = client
      @writer = writer
      @run_dir = run_dir
    end

    def reconcile_entity(mapper, start_cursor: nil)
      entity = mapper.entity
      local = mapper.local_scope.index_by { |rec| mapper.local_key(rec) }
      seen = load_seen(entity)
      counts = { entity: entity, local: local.size, cb: 0, matched: 0, identical: 0, changed: 0, cb_only: 0, local_only: 0 }

      @client.each_page(entity, start_cursor: start_cursor) do |rows, next_cursor|
        changed_rows = []
        cb_only_rows = []
        new_seen = []
        rows.each do |cb_row|
          counts[:cb] += 1
          key = mapper.cb_key(cb_row)
          rec = local[key]
          if rec.nil?
            counts[:cb_only] += 1
            cb_only_rows << { key: key, identifiers: mapper.identifiers(cb_row) }
          else
            counts[:matched] += 1
            new_seen << key
            diffs = mapper.field_diffs(rec, cb_row)
            if diffs.empty?
              counts[:identical] += 1
            else
              counts[:changed] += 1
              changed_rows << { key: key, diffs: diffs }
            end
          end
        end
        @writer.append_changed(entity, changed_rows) if changed_rows.any?
        @writer.append_cb_only(entity, cb_only_rows) if cb_only_rows.any?
        append_seen(entity, new_seen)
        new_seen.each { |k| seen << k }
        write_checkpoint(entity, next_cursor)
      end

      local_only = local.keys - seen.to_a
      counts[:local_only] = local_only.size
      @writer.append_local_only(entity, local_only)
      write_checkpoint(entity, nil, done: true)
      counts
    end

    private

    def checkpoint_path = File.join(@run_dir, "checkpoint.json")

    def write_checkpoint(entity, next_cursor, done: false)
      File.write(checkpoint_path, JSON.pretty_generate(entity: entity, next_cursor: next_cursor, done: done))
    end

    def load_seen(entity)
      path = @writer.seen_path(entity)
      set = Set.new
      File.foreach(path) { |line| set << JSON.parse(line.chomp) } if File.exist?(path)
      set
    end

    def append_seen(entity, keys)
      File.open(@writer.seen_path(entity), "a") { |f| keys.each { |k| f.puts(JSON.generate(k)) } }
    end
  end
end
