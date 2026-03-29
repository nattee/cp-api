require "test_helper"

class Scrapers::CuGetRegTest < ActiveSupport::TestCase
  setup do
    @semester = semesters(:sem_2568_1)
    @scraper = Scrapers::CuGetReg.new(semester: @semester, study_program: "S")
    @fixture_json = File.read(Rails.root.join("test/fixtures/scraper/cugetreg/2110101.json"))
    @fixture_response = JSON.parse(@fixture_json)
  end

  # --- Normalization ---

  test "fetch_course normalizes GraphQL response to common format" do
    stub_successful_request(@fixture_json)

    result = @scraper.fetch_course("2110101")

    assert_equal "2110101", result[:course_no]
    assert_equal "COMPUTER PROGRAMMING", result[:name_en]
    assert_equal "การเขียนโปรแกรมคอมพิวเตอร์", result[:name_th]
    assert_equal "Introduction to computer programming concepts.", result[:description_en]
    assert_equal "แนะนำแนวคิดการเขียนโปรแกรมคอมพิวเตอร์", result[:description_th]
    assert_equal 3.0, result[:credits]
    assert_equal 2, result[:sections].length
  end

  test "normalizes section data" do
    stub_successful_request(@fixture_json)

    result = @scraper.fetch_course("2110101")
    sec1 = result[:sections][0]

    assert_equal "1", sec1[:section_no]
    assert_equal "2CP", sec1[:note]
    assert_equal 58, sec1[:enrollment_current]
    assert_equal 60, sec1[:enrollment_max]
    assert_equal 2, sec1[:classes].length
  end

  test "normalizes class data" do
    stub_successful_request(@fixture_json)

    result = @scraper.fetch_course("2110101")
    cls = result[:sections][0][:classes][0]

    assert_equal "LECT", cls[:type]
    assert_equal "MO", cls[:day]
    assert_equal "09:30", cls[:start_time]
    assert_equal "11:00", cls[:end_time]
    assert_equal "ENG4", cls[:building]
    assert_equal "303", cls[:room]
    assert_equal ["JS"], cls[:teachers]
  end

  test "returns nil when course not found" do
    stub_successful_request('{"data":{"course":null}}')

    result = @scraper.fetch_course("9999999")
    assert_nil result
  end

  test "null note normalizes to nil" do
    stub_successful_request(@fixture_json)

    result = @scraper.fetch_course("2110101")
    sec2 = result[:sections][1]

    assert_nil sec2[:note]
  end

  # --- Import ---

  test "import_course_data creates offering, sections, time_slots, and teachings" do
    # Use sem_2568_2 to avoid fixture overlap with existing sem_2568_1 offerings
    scraper = Scrapers::CuGetReg.new(semester: semesters(:sem_2568_2), study_program: "S")
    stub_successful_request(@fixture_json, scraper)
    data = scraper.fetch_course("2110101")

    assert_difference -> { CourseOffering.count }, 1 do
      assert_difference -> { Section.count }, 2 do
        assert_difference -> { TimeSlot.count }, 3 do
          summary = scraper.import_course_data(data)

          assert_equal 2, summary[:sections]
          assert_equal 3, summary[:time_slots]
          assert_equal 3, summary[:teachings]  # JS in sec1 + JJ in sec2 + JS in sec2 (via dedup: JS once per section)
          assert_equal ["XYZ"], summary[:unresolved_teachers]
        end
      end
    end
  end

  test "import_course_data sets enrollment on sections" do
    stub_successful_request(@fixture_json)
    data = @scraper.fetch_course("2110101")

    @scraper.import_course_data(data)

    offering = CourseOffering.find_by(course: courses(:intro_computing), semester: @semester)
    sec1 = offering.sections.find_by(section_number: 1)
    assert_equal 58, sec1.enrollment_current
    assert_equal 60, sec1.enrollment_max
  end

  test "import_course_data updates course descriptions when blank" do
    course = courses(:intro_computing)
    assert_nil course.description

    stub_successful_request(@fixture_json)
    data = @scraper.fetch_course("2110101")
    @scraper.import_course_data(data)

    course.reload
    assert_equal "Introduction to computer programming concepts.", course.description
    assert_equal "แนะนำแนวคิดการเขียนโปรแกรมคอมพิวเตอร์", course.description_th
  end

  test "import_course_data does not overwrite existing descriptions" do
    course = courses(:intro_computing)
    course.update!(description: "Existing description")

    stub_successful_request(@fixture_json)
    data = @scraper.fetch_course("2110101")
    @scraper.import_course_data(data)

    course.reload
    assert_equal "Existing description", course.description
  end

  test "import_course_data skips course not in database" do
    data = { course_no: "9999999", sections: [] }
    summary = @scraper.import_course_data(data)

    assert summary[:skipped]
    assert_equal "course not in database", summary[:reason]
  end

  test "import_course_data is idempotent" do
    stub_successful_request(@fixture_json)
    data = @scraper.fetch_course("2110101")

    @scraper.import_course_data(data)

    assert_no_difference -> { [CourseOffering.count, Section.count, TimeSlot.count].sum } do
      @scraper.import_course_data(data)
    end
  end

  test "import_course_data resolves staff by initials" do
    stub_successful_request(@fixture_json)
    data = @scraper.fetch_course("2110101")

    @scraper.import_course_data(data)

    offering = CourseOffering.find_by(course: courses(:intro_computing), semester: @semester)
    sec1 = offering.sections.find_by(section_number: 1)
    assert_includes sec1.teachings.map(&:staff), staffs(:lecturer_smith)
  end

  # --- Error handling ---

  test "raises ScraperError after retries on timeout" do
    stub_request_with_error(Timeout::Error.new("execution expired"))

    error = assert_raises(Scrapers::ScraperError) do
      @scraper.fetch_course("2110101")
    end
    assert_match(/failed after/, error.message)
  end

  test "raises ScraperError on HTTP error after retries" do
    stub_request_with_http_error(500, "Internal Server Error")

    error = assert_raises(Scrapers::ScraperError) do
      @scraper.fetch_course("2110101")
    end
    assert_match(/HTTP 500/, error.message)
  end

  test "raises ScraperError on invalid JSON" do
    stub_successful_request("not json at all")

    error = assert_raises(Scrapers::ScraperError) do
      @scraper.fetch_course("2110101")
    end
    assert_match(/invalid JSON/, error.message)
  end

  test "source_name returns cugetreg" do
    assert_equal "cugetreg", @scraper.source_name
  end

  # --- Console helpers ---

  test "scrape class method returns normalized hash" do
    result = with_stubbed_new(@fixture_json) do
      Scrapers::CuGetReg.scrape("2110101", 2568, 1)
    end

    assert_equal "2110101", result[:course_no]
    assert_equal 2, result[:sections].length
  end

  test "scrape class method does not persist semester" do
    Semester.find_by(year_be: 2570, semester_number: 1)&.destroy

    with_stubbed_new('{"data":{"course":null}}') do
      Scrapers::CuGetReg.scrape("2110101", 2570, 1)
    end

    assert_nil Semester.find_by(year_be: 2570, semester_number: 1)
  end

  test "scrape class method returns nil when course not found" do
    result = with_stubbed_new('{"data":{"course":null}}') do
      Scrapers::CuGetReg.scrape("9999999", 2568, 1)
    end
    assert_nil result
  end

  test "scrape class method passes study_program to constructor" do
    captured_program = nil
    original_new = Scrapers::CuGetReg.method(:new)

    Scrapers::CuGetReg.define_singleton_method(:new) do |**kwargs|
      captured_program = kwargs[:study_program]
      instance = original_new.call(**kwargs)
      instance.define_singleton_method(:execute_query) { |_| JSON.parse('{"data":{"course":null}}') }
      instance
    end

    Scrapers::CuGetReg.scrape("2110101", 2568, 1, "I")
    assert_equal "I", captured_program
  ensure
    Scrapers::CuGetReg.define_singleton_method(:new, original_new)
  end

  test "scrape! class method imports into database" do
    assert_difference -> { CourseOffering.count }, 1 do
      with_stubbed_new(@fixture_json) do
        Scrapers::CuGetReg.scrape!("2110101", 2568, 2)
      end
    end
  end

  test "scrape! class method creates semester if not exists" do
    Semester.find_by(year_be: 2570, semester_number: 3)&.destroy

    with_stubbed_new(@fixture_json) do
      Scrapers::CuGetReg.scrape!("2110101", 2570, 3)
    end

    assert Semester.find_by(year_be: 2570, semester_number: 3)
  end

  test "scrape! returns not_found hash when course not on server" do
    result = with_stubbed_new('{"data":{"course":null}}') do
      Scrapers::CuGetReg.scrape!("9999999", 2568, 1)
    end
    assert result[:not_found]
  end

  private

  def stub_successful_request(body, target_scraper = @scraper)
    target_scraper.define_singleton_method(:execute_query) do |course_no|
      parsed = JSON.parse(body)
      parsed
    rescue JSON::ParserError => e
      raise Scrapers::ScraperError, "cugetreg returned invalid JSON for course #{course_no}: #{e.message}"
    end
  end

  def stub_request_with_error(error)
    attempt = 0
    @scraper.define_singleton_method(:execute_query) do |course_no|
      # Override to always raise — simulates all retries exhausted
      raise Scrapers::ScraperError, "cugetreg failed after 4 attempts for course #{course_no}: #{error.message}"
    end
  end

  def stub_request_with_http_error(code, message)
    @scraper.define_singleton_method(:execute_query) do |course_no|
      raise Scrapers::ScraperError, "cugetreg failed after 4 attempts for course #{course_no}: HTTP #{code}: #{message}"
    end
  end

  # Temporarily overrides CuGetReg.new so every instance created in the block
  # has execute_query stubbed to return parsed JSON from `body`.
  def with_stubbed_new(body)
    original_new = Scrapers::CuGetReg.method(:new)

    Scrapers::CuGetReg.define_singleton_method(:new) do |**kwargs|
      instance = original_new.call(**kwargs)
      instance.define_singleton_method(:execute_query) do |course_no|
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Scrapers::ScraperError, "cugetreg returned invalid JSON for course #{course_no}: #{e.message}"
      end
      instance
    end

    yield
  ensure
    Scrapers::CuGetReg.define_singleton_method(:new, original_new)
  end
end
