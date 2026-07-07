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

  desc "Report-only: CSV of course_nos linked to the same program at more than one revision " \
       "(legacy CSV link vs ChulaBooster link). Never modifies data."
  task report_duplicate_revisions: :environment do
    require "csv"
    path = Rails.root.join("tmp", "duplicate_revision_links-#{Time.zone.now.strftime('%Y%m%d-%H%M%S')}.csv")
    count = 0
    CSV.open(path, "w") do |csv|
      csv << %w[program_code course_no revision_year_be course_group_code link_created_at]
      Program.find_each do |program|
        program.program_courses.includes(:course)
               .group_by { |pc| pc.course.course_no }
               .select { |_, links| links.size > 1 }
               .sort.each do |course_no, links|
          count += 1
          links.sort_by { |pc| pc.course.revision_year_be }.each do |pc|
            csv << [program.program_code, course_no, pc.course.revision_year_be,
                    pc.course_group_code, pc.created_at]
          end
        end
      end
    end
    puts "duplicated course_nos: #{count}"
    puts "→ #{path}"
  end
end
