require "net/http"
require "json"

module Scrapers
  class CuGetReg < Base
    ENDPOINT = "https://cugetreg.com/_api/graphql"

    COURSE_QUERY = <<~GRAPHQL
      query($courseNo: String!, $semester: String!, $academicYear: String!, $studyProgram: StudyProgram!) {
        course(
          courseNo: $courseNo
          courseGroup: { semester: $semester, academicYear: $academicYear, studyProgram: $studyProgram }
        ) {
          courseNo courseNameEn courseNameTh courseDescEn courseDescTh credit
          sections {
            sectionNo closed note
            capacity { current max }
            classes {
              type dayOfWeek
              period { start end }
              building room teachers
            }
          }
        }
      }
    GRAPHQL

    def source_name
      "cugetreg"
    end

    def fetch_course(course_no)
      response = execute_query(course_no)
      course_data = response.dig("data", "course")
      return nil if course_data.nil?

      normalize(course_data)
    end

    # Console helper: fetch and normalize a single course (no DB writes)
    #   Scrapers::CuGetReg.scrape("2110327", 2568, 2)
    def self.scrape(course_no, year_be, semester_number, study_program = "S")
      semester = Semester.find_or_initialize_by(year_be: year_be, semester_number: semester_number)
      scraper = new(semester: semester, study_program: study_program)
      scraper.fetch_course(course_no)
    end

    # Console helper: fetch, normalize, and import into DB
    #   Scrapers::CuGetReg.scrape!("2110327", 2568, 2)
    def self.scrape!(course_no, year_be, semester_number, study_program = "S")
      semester = Semester.find_or_create_by!(year_be: year_be, semester_number: semester_number)
      scraper = new(semester: semester, study_program: study_program)
      data = scraper.fetch_course(course_no)
      return { not_found: true } if data.nil?

      scraper.import_course_data(data)
    end

    private

    def execute_query(course_no)
      body = {
        query: COURSE_QUERY,
        variables: {
          courseNo: course_no,
          semester: semester.semester_number.to_s,
          academicYear: semester.year_be.to_s,
          studyProgram: study_program
        }
      }

      uri = URI(ENDPOINT)
      attempt = 0

      begin
        attempt += 1
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
          open_timeout: config[:request_timeout],
          read_timeout: config[:request_timeout]
        ) do |http|
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = body.to_json
          http.request(req)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestError, "HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
        end

        JSON.parse(response.body)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, RequestError => e
        if attempt <= config[:retry_count]
          sleep(config[:retry_delay])
          retry
        end
        raise ScraperError, "#{source_name} failed after #{attempt} attempts for course #{course_no}: #{e.message}"
      rescue JSON::ParserError => e
        raise ScraperError, "#{source_name} returned invalid JSON for course #{course_no}: #{e.message}"
      end
    end

    def normalize(data)
      {
        course_no: data["courseNo"],
        name_en: data["courseNameEn"],
        name_th: data["courseNameTh"],
        description_en: data["courseDescEn"].presence,
        description_th: data["courseDescTh"].presence,
        credits: data["credit"]&.to_f,
        sections: (data["sections"] || []).map { |sec| normalize_section(sec) }
      }
    end

    def normalize_section(sec)
      {
        section_no: sec["sectionNo"],
        note: sec["note"].presence,
        enrollment_current: sec.dig("capacity", "current"),
        enrollment_max: sec.dig("capacity", "max"),
        classes: (sec["classes"] || []).map { |cls| normalize_class(cls) }
      }
    end

    def normalize_class(cls)
      {
        type: cls["type"],
        day: cls["dayOfWeek"],
        start_time: cls.dig("period", "start"),
        end_time: cls.dig("period", "end"),
        building: cls["building"].presence,
        room: cls["room"].presence,
        teachers: cls["teachers"] || []
      }
    end
  end

  class ScraperError < StandardError; end
  class RequestError < StandardError; end
end
