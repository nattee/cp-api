namespace :program_courses do
  desc "One-time backfill of program_courses.course_group_code from the deprecated " \
       "courses.course_group string. Run chulabooster:sync_program_courses FIRST so CB wins " \
       "where both sources know the answer. DRY-RUN by default; COMMIT=1 to write."
  task backfill_legacy_groups: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "legacy_group_backfill", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — pairings WILL be created/tagged" : "MODE: dry-run — no database writes"
    counts = LegacyCourseGroupBackfill.new(run_dir: run_dir, commit: commit).call

    puts
    puts "legacy course rows:     #{counts[:legacy_rows]}"
    puts "unparseable (skipped):  #{counts[:unparseable]}   <- skipped_rows.csv"
    puts "identical:              #{counts[:identical]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "#{commit ? 'tags filled:           ' : 'tags fillable:         '} #{counts[commit ? :filled : :fillable]}"
    puts "tag discrepancies:      #{counts[:tag_discrepancies]}   <- review tag_discrepancies.csv"
    puts "placeholder links:      #{counts[:placeholder_links]}   <- placeholder_links.csv (left alone)"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
end
