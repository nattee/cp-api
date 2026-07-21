require "test_helper"

class Line::Tools::SemesterOverviewToolTest < ActiveSupport::TestCase
  # Fixtures: sem_2568_1 has 2 offerings (2110101 confirmed ×2 sections,
  # 2110499 planned ×1 section); sem_2567_1 has 2 offerings (2110101 ×2
  # sections, 2103106 ×1 section).

  test "explicit semester returns counts and per-program breakdown" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2568/1" }))

    assert_equal "2568/1", result["semester"]
    assert_equal 2, result["offerings"]
    assert_equal 3, result["sections"]
    assert_equal 2, result["distinct_courses"]
    assert result["by_program"].is_a?(Array)
    assert result["by_program"].all? { |row| row["program"].present? && row["offerings"].positive? }
  end

  test "omitted semester defaults to the latest" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({}))
    assert_equal Semester.ordered.first.display_name, result["semester"]
  end

  test "unknown semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2500/1" }))
    assert_match(/No semester 2500\/1/, result["error"])
  end

  test "unparseable semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "next term" }))
    assert_match(/Could not parse semester/, result["error"])
  end
end
