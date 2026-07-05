require "json"

module Chulabooster
  # Read-only stand-in for Client that serves rows already dumped by Snapshotter, instead
  # of hitting the network. Same each_page/each_row interface as Client, so Reconciler (and
  # anything else built against Client) runs unmodified against a cached snapshot.
  class SnapshotClient
    def initialize(dir)
      @dir = dir
    end

    def each_page(entity, changed_since: nil, start_cursor: nil)
      path = File.join(@dir, "#{entity}.jsonl")
      raise Chulabooster::Error, "no snapshot for #{entity} in #{@dir}" unless File.exist?(path)

      rows = File.foreach(path).map { |line| JSON.parse(line) }
      yield rows, nil
    end

    def each_row(entity, **opts, &blk) = each_page(entity, **opts) { |rows, _| rows.each(&blk) }
  end
end
