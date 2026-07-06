namespace :chulabooster do
  desc "Snapshot raw ChulaBooster export data to disk (JSONL per entity) so reconciliation " \
       "and analysis can run offline without re-hitting CB. RESUME=tmp/chulabooster_snapshot/<ts> to resume."
  task snapshot: :environment do
    $stdout.sync = true

    resume_dir = ENV["RESUME"]
    dir = resume_dir || Rails.root.join("tmp", "chulabooster_snapshot", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client = Chulabooster::Client.new
    snapshotter = Chulabooster::Snapshotter.new(client: client, dir: dir)

    Chulabooster::Client::EXPORT_ENTITIES.each do |entity|
      if snapshotter.done?(entity)
        puts "= #{entity}: already complete, skipping"
        next
      end
      cursor = snapshotter.resume_cursor(entity)
      puts "→ #{entity}#{cursor ? " (resuming)" : ""}..."
      count = snapshotter.dump_entity(entity, start_cursor: cursor)
      puts "  #{entity}: #{count} rows"
    end

    puts "\n→ snapshot dir: #{dir}"
  end

  desc "Read-only reconciliation of ChulaBooster exports vs local DB. RESUME=tmp/reconciliation/<ts> to resume. " \
       "SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to reconcile against a cached snapshot instead of live CB."
  task reconcile: :environment do
    $stdout.sync = true

    resume_dir = ENV["RESUME"]
    run_dir = resume_dir || Rails.root.join("tmp", "reconciliation", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    writer  = Chulabooster::ReportWriter.new(run_dir)
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
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

  desc "Create local Students for CB-only students + report discrepancies. DRY-RUN by default; " \
       "COMMIT=1 to write. SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_students: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — new students WILL be created" : "MODE: dry-run — no database writes"
    counts = Chulabooster::StudentSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "matched:                #{counts[:matched]}"
    puts "cb_only:                #{counts[:cb_only]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "  heuristic-flagged:    #{counts[:heuristic_flagged]}"
    puts "  twin-flagged:         #{counts[:twin_flagged]}"
    puts "unresolved (skipped):   #{counts[:unresolved]}"
    puts "row errors:             #{counts[:errors]}"
    puts "unknown status codes:   #{counts[:unknown_status]}"
    puts "program discrepancies:  #{counts[:program_discrepancies]}   <- review students_program_discrepancies.csv"
    puts "status discrepancies:   #{counts[:status_discrepancies]} (#{counts[:stale_active]} locally-active look stale)"
    puts "\n→ reports: #{run_dir}"
  end

  desc "Create CB-only Courses + backfill local auto-generated shells from CB metadata. " \
       "DRY-RUN by default; COMMIT=1 to write. SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_courses: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync_courses", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — courses WILL be created/backfilled" : "MODE: dry-run — no database writes"
    counts = Chulabooster::CourseSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "cb rows:                #{counts[:cb_rows]}"
    puts "matched (real):         #{counts[:matched_real]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "#{commit ? 'backfilled:            ' : 'backfillable:          '} #{counts[commit ? :backfilled : :backfillable]}"
    puts "discrepancies (real):   #{counts[:discrepancies]}   <- review course_discrepancies.csv"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
end
