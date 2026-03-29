require "net/http"
require "nokogiri"
require "openssl"

module Scrapers
  class CasReg < Base
    BASE_HOST = "cas.reg.chula.ac.th"
    INIT_PATH = "/servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.QueryCourseScheduleNewServlet"
    LIST_PATH = "/servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.CourseListNewServlet"
    DETAIL_PATH = "/servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.CourseScheduleDtlNewServlet"

    NOT_READY_PATTERN = /ระบบยังไม่พร้อม/

    def source_name
      "cas_reg"
    end

    def fetch_course(course_no)
      html = fetch_detail_page(course_no)
      return nil if html.nil? || html.strip.empty?

      doc = Nokogiri::HTML(html)
      parse_detail(doc, course_no)
    end

    # Console helper: fetch and normalize (no DB writes)
    def self.scrape(course_no, year_be, semester_number, study_program = "S")
      semester = Semester.find_or_initialize_by(year_be: year_be, semester_number: semester_number)
      scraper = new(semester: semester, study_program: study_program)
      scraper.fetch_course(course_no)
    end

    # Console helper: fetch, normalize, and import into DB
    def self.scrape!(course_no, year_be, semester_number, study_program = "S")
      semester = Semester.find_or_create_by!(year_be: year_be, semester_number: semester_number)
      scraper = new(semester: semester, study_program: study_program)
      data = scraper.fetch_course(course_no)
      return { not_found: true } if data.nil?

      scraper.import_course_data(data)
    end

    private

    def fetch_detail_page(course_no)
      ensure_session!

      # Must hit the course list first to set server-side session state
      list_params = URI.encode_www_form(
        studyProgram: study_program,
        semester: semester.semester_number.to_s,
        acadyearEfd: semester.year_be.to_s,
        courseno: course_no,
        acadyear: semester.year_be.to_s,
        lang: "T"
      )
      http_client.get("#{LIST_PATH}?#{list_params}", "Cookie" => @cookies)

      detail_params = URI.encode_www_form(
        courseNo: course_no,
        studyProgram: study_program,
        semester: semester.semester_number.to_s,
        acadyear: semester.year_be.to_s
      )

      attempt = 0
      begin
        attempt += 1
        response = http_client.get("#{DETAIL_PATH}?#{detail_params}", "Cookie" => @cookies)

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestError, "HTTP #{response.code}"
        end

        body = decode_response(response)

        if body.match?(NOT_READY_PATTERN)
          raise RequestError, "System not ready"
        end

        # Short response means no data / course not found
        return nil if body.length < 500

        body
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, RequestError => e
        if attempt <= config[:retry_count]
          sleep(config[:retry_delay])
          @session_initialized = false
          ensure_session!
          retry
        end
        raise ScraperError, "#{source_name} failed after #{attempt} attempts for course #{course_no}: #{e.message}"
      end
    end

    def ensure_session!
      return if @session_initialized

      response = http_client.get(INIT_PATH)
      @cookies = response.get_fields("set-cookie")&.map { |c| c.split(";").first }&.join("; ") || ""
      @session_initialized = true
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError => e
      raise ScraperError, "#{source_name} session init failed: #{e.message}"
    end

    def http_client
      @http_client ||= begin
        http = Net::HTTP.new(BASE_HOST, 443)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.open_timeout = config[:request_timeout]
        http.read_timeout = config[:request_timeout]
        http
      end
    end

    def decode_response(response)
      body = response.body
      body.force_encoding("TIS-620").encode("UTF-8", invalid: :replace, undef: :replace)
    rescue Encoding::UndefinedConversionError
      body.force_encoding("UTF-8")
    end

    def parse_detail(doc, course_no)
      # Extract course info from Table2
      table2 = doc.at_css("table#Table2")
      name_en = nil
      name_th = nil
      credits = nil

      if table2
        rows = table2.css("tr")
        rows.each do |row|
          text = clean_cell(row.text)
          next if text.blank?
          # English name row: contains only ASCII + spaces, all caps or title case
          if text.match?(/\A[A-Z][A-Z &\-\/().]+\z/)
            name_en = text
          # Thai name row
          elsif text.match?(/[\u0E00-\u0E7F]/) && !text.match?(/ปีการศึกษา|ทวิภาค|ไตรภาค|คณะ/)
            name_th = text unless text.match?(/\d{7}/) # skip "2110101 COMP PROG" line
          end
        end
      end

      # Extract credits from credit table
      credit_table = doc.at_css("table:not(#Table2):not(#Table3):not(#Table4):not(#dw)")
      if credit_table
        credit_text = clean_cell(credit_table.text)
        credit_match = credit_text&.match(/(\d+\.?\d*)\s*CREDIT/)
        credits = credit_match[1].to_f if credit_match
      end

      # Parse section data from Table3
      data_table = doc.at_css("table#Table3")
      return nil unless data_table

      sections = parse_sections(data_table)
      return nil if sections.empty?

      {
        course_no: course_no,
        name_en: name_en,
        name_th: name_th,
        description_en: nil,
        description_th: nil,
        credits: credits,
        sections: sections
      }
    end

    def parse_sections(table)
      # Skip header row (bgcolor="#FFCCFF") and empty first row
      rows = table.css("tr").reject { |r| r["bgcolor"] || r.css("td").empty? }

      sections = []
      current_section = nil

      rows.each do |row|
        cells = row.css("td")
        next if cells.length < 9

        # Real HTML structure: 10 cells
        # [0] empty spacer, [1] section_no, [2] method, [3] day, [4] time,
        # [5] building, [6] room, [7] teacher, [8] remark, [9] enrollment
        cell_texts = cells.map { |td| clean_cell(td.text) }

        # Cell[1] may contain "2 LECT TH 8:00..." due to malformed HTML (unclosed TD).
        # Extract only the leading digits as section number.
        raw_section = cell_texts[1]
        section_no = raw_section&.match(/\A(\d+)/)&.captures&.first
        method = cell_texts[2]
        day = cell_texts[3]
        time = cell_texts[4]
        building = cell_texts[5]
        room = cell_texts[6]
        teachers_str = cell_texts[7]
        remark = cell_texts[8]
        enrollment_str = cell_texts[9]

        if section_no.present?
          enrollment_current, enrollment_max = parse_enrollment(enrollment_str)
          current_section = {
            section_no: section_no,
            note: remark.presence,
            enrollment_current: enrollment_current,
            enrollment_max: enrollment_max,
            classes: []
          }
          sections << current_section
        end

        next unless current_section

        start_time, end_time = parse_time_range(time)
        next if start_time.nil?

        current_section[:classes] << {
          type: method.presence,
          day: day.presence,
          start_time: start_time,
          end_time: end_time,
          building: building.presence,
          room: room.presence,
          teachers: parse_teachers(teachers_str)
        }
      end

      sections
    end

    def clean_cell(text)
      text.gsub(/[\u00A0\s]+/, " ").strip.presence
    end

    def parse_time_range(time_str)
      return [nil, nil] if time_str.blank?
      match = time_str.match(/(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})/)
      return [nil, nil] unless match
      [format("%02d:%s", match[1].to_i, match[2]), format("%02d:%s", match[3].to_i, match[4])]
    end

    def parse_enrollment(str)
      return [nil, nil] if str.blank?
      match = str.match(/(\d+)\s*\/\s*(\d+)/)
      return [nil, nil] unless match
      [match[1].to_i, match[2].to_i]
    end

    def parse_teachers(str)
      return [] if str.blank?
      str.split(/[,\/]/).map(&:strip).reject(&:blank?)
    end
  end
end
