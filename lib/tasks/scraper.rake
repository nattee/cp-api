namespace :scraper do
  desc "Scrape course schedules from external source. SOURCE=cugetreg|cas_reg YEAR=2568 SEMESTER=2 PROGRAM=S LIMIT=10"
  task run: :environment do
    $stdout.sync = true
    source_name = ENV.fetch("SOURCE", "cugetreg")
    year_be = ENV.fetch("YEAR").to_i
    semester_number = ENV.fetch("SEMESTER").to_i
    study_program = ENV.fetch("PROGRAM", "S")

    semester = Semester.find_or_create_by!(year_be: year_be, semester_number: semester_number)

    klass = case source_name
            when "cugetreg" then Scrapers::CuGetReg
            when "cas_reg" then Scrapers::CasReg
            else abort "Unknown SOURCE: #{source_name}. Use cugetreg or cas_reg."
            end

    source = klass.new(semester: semester, study_program: study_program)
    courses = Course.all
    courses = courses.limit(ENV["LIMIT"].to_i) if ENV["LIMIT"].present?
    total = courses.count

    scraper_config = Rails.application.config_for(:scraper)
    rate_delay = 1.0 / scraper_config[:rate_limit]

    # Create a Scrape record for history
    scrape = Scrape.create!(
      semester: semester,
      user: User.first,
      source: source_name,
      study_program: study_program,
      state: "running",
      total_courses: total
    )

    puts "Scraping #{year_be}/#{semester_number} via #{source_name} (#{total} courses)..."

    found = 0
    not_found = 0
    errors = 0
    all_unresolved = []
    error_log = []

    courses.find_each.with_index(1) do |course, idx|
      begin
        data = source.fetch_course(course.course_no)

        if data.nil?
          not_found += 1
          puts "  [#{idx}/#{total}]  #{course.course_no}  — not found this semester"
        else
          summary = source.import_course_data(data)
          if summary[:skipped]
            not_found += 1
            puts "  [#{idx}/#{total}]  #{course.course_no}  — #{summary[:reason]}"
          else
            found += 1
            all_unresolved.concat(summary[:unresolved_teachers])
            puts "  [#{idx}/#{total}]  #{course.course_no}  ✓ #{summary[:sections]} sections, #{summary[:time_slots]} time slots"
          end
        end
      rescue => e
        errors += 1
        error_log << { course_no: course.course_no, error: e.message }
        puts "  [#{idx}/#{total}]  #{course.course_no}  ✗ #{e.class}: #{e.message}"
      end

      sleep(rate_delay)
    end

    scrape.update!(
      state: "completed",
      courses_found: found,
      courses_not_found: not_found,
      sections_count: 0,
      time_slots_count: 0,
      unresolved_teachers: all_unresolved.uniq.presence,
      error_log: error_log.presence
    )

    puts "Done. #{found} found, #{not_found} not offered, #{errors} errors."
    if all_unresolved.uniq.any?
      puts "Unresolved teachers: #{all_unresolved.uniq.join(', ')}"
    end
  end
end
