require "test_helper"

class ScrapeTest < ActiveSupport::TestCase
  test "valid scrape" do
    scrape = Scrape.new(
      semester: semesters(:sem_2568_1),
      user: users(:admin),
      source: "cugetreg",
      study_program: "S",
      state: "pending"
    )
    assert scrape.valid?
  end

  test "requires source" do
    scrape = scrapes(:completed_scrape).dup
    scrape.source = nil
    assert_not scrape.valid?
  end

  test "source must be valid" do
    scrape = scrapes(:completed_scrape).dup
    scrape.source = "invalid"
    assert_not scrape.valid?
  end

  test "requires state" do
    scrape = scrapes(:completed_scrape).dup
    scrape.state = nil
    assert_not scrape.valid?
  end

  test "state must be valid" do
    scrape = scrapes(:completed_scrape).dup
    scrape.state = "invalid"
    assert_not scrape.valid?
  end

  test "running? returns true when state is running" do
    assert scrapes(:running_scrape).running?
    assert_not scrapes(:completed_scrape).running?
  end

  test "completed? returns true when state is completed" do
    assert scrapes(:completed_scrape).completed?
    assert_not scrapes(:running_scrape).completed?
  end

  test "source_label returns human-readable name" do
    assert_equal "CuGetReg", scrapes(:completed_scrape).source_label
    assert_equal "CAS Reg Chula", scrapes(:running_scrape).source_label
  end
end
