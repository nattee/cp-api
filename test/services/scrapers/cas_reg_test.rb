require "test_helper"

class Scrapers::CasRegTest < ActiveSupport::TestCase
  setup do
    @semester = semesters(:sem_2568_1)
    @scraper = Scrapers::CasReg.new(semester: @semester, study_program: "S")
    @fixture_html = File.read(Rails.root.join("test/fixtures/scraper/cas_reg/2110101.html"))
  end

  # --- Normalization ---

  test "fetch_course normalizes HTML response to common format" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")

    assert_equal "2110101", result[:course_no]
    assert_equal "COMPUTER PROGRAMMING", result[:name_en]
    assert_equal "การทำโปรแกรมคอมพิวเตอร์", result[:name_th]
    assert_nil result[:description_en]
    assert_nil result[:description_th]
    assert_equal 3.0, result[:credits]
    assert_equal 6, result[:sections].length
  end

  test "normalizes section data" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")
    sec1 = result[:sections][0]

    assert_equal "1", sec1[:section_no]
    assert_equal 70, sec1[:enrollment_current]
    assert_equal 80, sec1[:enrollment_max]
    assert_equal 1, sec1[:classes].length
  end

  test "normalizes class data" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")
    cls = result[:sections][0][:classes][0]

    assert_equal "LECT", cls[:type]
    assert_equal "TH", cls[:day]
    assert_equal "08:00", cls[:start_time]
    assert_equal "11:00", cls[:end_time]
    assert_equal "ENG3", cls[:building]
    assert_equal "218", cls[:room]
    assert_equal ["CNP"], cls[:teachers]
  end

  test "parses section remark with line breaks" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")
    sec1 = result[:sections][0]

    assert sec1[:note]&.include?("YEAR1")
  end

  test "returns nil when course not found" do
    stub_fetch(nil)

    result = @scraper.fetch_course("9999999")
    assert_nil result
  end

  test "parses all 6 sections from real HTML" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")
    section_nos = result[:sections].map { |s| s[:section_no] }

    assert_equal %w[1 2 3 4 5 11], section_nos
  end

  test "parses enrollment for each section" do
    stub_fetch(@fixture_html)

    result = @scraper.fetch_course("2110101")
    enrollments = result[:sections].map { |s| [s[:enrollment_current], s[:enrollment_max]] }

    assert_equal [70, 80], enrollments[0]
    assert_equal [76, 80], enrollments[1]
    assert_equal [86, 105], enrollments[4]  # section 5
    assert_equal [24, 50], enrollments[5]   # section 11
  end

  # --- Import ---

  test "import_course_data creates records from parsed HTML" do
    scraper = Scrapers::CasReg.new(semester: semesters(:sem_2568_2), study_program: "S")
    stub_fetch(@fixture_html, scraper)
    data = scraper.fetch_course("2110101")

    assert_difference -> { CourseOffering.count }, 1 do
      assert_difference -> { Section.count }, 6 do
        summary = scraper.import_course_data(data)
        assert_equal 6, summary[:sections]
        assert_equal 6, summary[:time_slots]
      end
    end
  end

  # --- Error handling ---

  test "raises ScraperError after retries" do
    @scraper.define_singleton_method(:fetch_detail_page) do |course_no|
      raise Scrapers::ScraperError, "cas_reg failed after 4 attempts for course #{course_no}: HTTP 500"
    end

    error = assert_raises(Scrapers::ScraperError) do
      @scraper.fetch_course("2110101")
    end
    assert_match(/failed after/, error.message)
  end

  test "source_name returns cas_reg" do
    assert_equal "cas_reg", @scraper.source_name
  end

  # --- Console helpers ---

  test "scrape class method returns normalized hash" do
    result = with_stubbed_new(@fixture_html) do
      Scrapers::CasReg.scrape("2110101", 2568, 1)
    end

    assert_equal "2110101", result[:course_no]
    assert_equal 6, result[:sections].length
  end

  test "scrape! class method imports into database" do
    assert_difference -> { CourseOffering.count }, 1 do
      with_stubbed_new(@fixture_html) do
        Scrapers::CasReg.scrape!("2110101", 2568, 2)
      end
    end
  end

  test "scrape! returns not_found when course not on server" do
    result = with_stubbed_new(nil) do
      Scrapers::CasReg.scrape!("9999999", 2568, 1)
    end
    assert result[:not_found]
  end

  private

  def stub_fetch(html, target_scraper = @scraper)
    target_scraper.define_singleton_method(:fetch_detail_page) do |course_no|
      html
    end
  end

  def with_stubbed_new(html)
    original_new = Scrapers::CasReg.method(:new)

    Scrapers::CasReg.define_singleton_method(:new) do |**kwargs|
      instance = original_new.call(**kwargs)
      instance.define_singleton_method(:fetch_detail_page) do |course_no|
        html
      end
      instance
    end

    yield
  ensure
    Scrapers::CasReg.define_singleton_method(:new, original_new)
  end
end
