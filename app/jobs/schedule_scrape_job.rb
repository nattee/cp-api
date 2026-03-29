class ScheduleScrapeJob < ApplicationJob
  queue_as :default

  def perform(scrape_id)
    scrape = Scrape.find(scrape_id)
    scrape.update!(state: "running")

    source = build_source(scrape)
    courses = Course.all
    scrape.update!(total_courses: courses.count)

    scraper_config = Rails.application.config_for(:scraper)
    rate_delay = 1.0 / scraper_config[:rate_limit]

    courses_found = 0
    courses_not_found = 0
    sections_count = 0
    time_slots_count = 0
    unresolved_teachers = []
    error_log = []

    courses.find_each do |course|
      begin
        data = source.fetch_course(course.course_no)

        if data.nil?
          courses_not_found += 1
        else
          summary = source.import_course_data(data)
          if summary[:skipped]
            courses_not_found += 1
          else
            courses_found += 1
            sections_count += summary[:sections]
            time_slots_count += summary[:time_slots]
            unresolved_teachers.concat(summary[:unresolved_teachers])
          end
        end
      rescue Scrapers::ScraperError => e
        error_log << { course_no: course.course_no, error: e.message }
        ApiEvent.log(
          service: "scraper",
          action: "fetch_course",
          message: "#{source.source_name}: #{e.message}",
          details: { course_no: course.course_no, scrape_id: scrape.id }
        )
      end

      scrape.update!(
        courses_found: courses_found,
        courses_not_found: courses_not_found,
        sections_count: sections_count,
        time_slots_count: time_slots_count
      )

      sleep(rate_delay)
    end

    scrape.update!(
      state: "completed",
      unresolved_teachers: unresolved_teachers.uniq,
      error_log: error_log.presence
    )
  rescue => e
    scrape&.update!(state: "failed", error_message: e.message)
    raise
  end

  private

  def build_source(scrape)
    klass = case scrape.source
            when "cugetreg" then Scrapers::CuGetReg
            when "cas_reg" then Scrapers::CasReg
            else raise "Unknown source: #{scrape.source}"
            end
    klass.new(semester: scrape.semester, study_program: scrape.study_program)
  end
end
