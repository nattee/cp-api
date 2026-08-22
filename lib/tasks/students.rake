namespace :students do
  desc "Backfill students.study_track from the dept enrollment label + CB evidence. " \
       "Dry-run by default; COMMIT=1 to write, SNAPSHOT_DIR= to read a CB snapshot instead of live."
  task backfill_study_track: :environment do
    client = ENV["SNAPSHOT_DIR"].present? ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    cb_rows = {}
    client.each_row("students") { |row| cb_rows[row["student_id"].to_s] = row }
    puts "CB students loaded: #{cb_rows.size}"
    StudyTrackBackfill.new(cb_rows: cb_rows, commit: ENV["COMMIT"] == "1").run
  end
end
