namespace :chulabooster do
  desc "Read-only reconciliation of ChulaBooster exports vs local DB. RESUME=tmp/reconciliation/<ts> to resume."
  task reconcile: :environment do
    $stdout.sync = true

    resume_dir = ENV["RESUME"]
    run_dir = resume_dir || Rails.root.join("tmp", "reconciliation", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    writer  = Chulabooster::ReportWriter.new(run_dir)
    client  = Chulabooster::Client.new
    reconciler = Chulabooster::Reconciler.new(client: client, writer: writer, run_dir: run_dir)

    checkpoint = Chulabooster.load_checkpoint(run_dir)
    counts = []

    Chulabooster.mappers.each do |mapper|
      entity = mapper.entity
      if checkpoint[:completed].include?(entity)
        puts "= #{entity}: already complete, skipping"
        counts << writer.read_counts(entity)
        next
      end
      start_cursor = (checkpoint[:in_progress] == entity) ? checkpoint[:next_cursor] : nil
      puts "→ #{entity}#{start_cursor ? " (resuming)" : ""}..."
      counts << reconciler.reconcile_entity(mapper, start_cursor: start_cursor)
    end

    puts "\n#{writer.write_summary(counts.compact)}\n\n→ files: #{run_dir}"
  end
end
