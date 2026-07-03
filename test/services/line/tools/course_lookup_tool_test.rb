require "test_helper"

class Line::Tools::CourseLookupToolTest < ActiveSupport::TestCase
  # Fixtures: intro_computing (2110101, Introduction to Computing, rev 2565, CP),
  #           senior_project (2110499, Senior Project / SR PROJ, rev 2565, CP),
  #           gened_course (2103106, General Physics, rev 2560, CP)

  # --- Search by course number ---

  test "finds course by exact course number" do
    result = call_tool(query: "2110101")
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
    assert_equal "2110101", data["courses"].first["course_no"]
  end

  test "finds courses by course number prefix" do
    result = call_tool(query: "2110")
    data = JSON.parse(result)
    assert_equal 2, data["courses"].size
    assert_equal %w[2110101 2110499], data["courses"].map { |c| c["course_no"] }
  end

  test "returns empty for non-matching course number" do
    result = call_tool(query: "9999")
    data = JSON.parse(result)
    assert_equal 0, data["courses"].size
  end

  # --- Search by name ---

  test "finds course by English name" do
    result = call_tool(query: "Computing")
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
    assert_equal "2110101", data["courses"].first["course_no"]
  end

  test "finds course by Thai name" do
    result = call_tool(query: "โครงงาน")
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
    assert_equal "2110499", data["courses"].first["course_no"]
  end

  test "finds course by abbreviated name" do
    result = call_tool(query: "SR PROJ")
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
    assert_equal "2110499", data["courses"].first["course_no"]
  end

  test "name search is case-insensitive partial match" do
    result = call_tool(query: "computing")
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
  end

  # --- Filters ---

  test "filters by program_code" do
    result = call_tool(program_code: "CP")
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  test "program_code is case-insensitive" do
    result = call_tool(program_code: "cp")
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  test "filters by revision_year" do
    result = call_tool(revision_year: 2560)
    data = JSON.parse(result)
    assert_equal 1, data["courses"].size
    assert_equal "2103106", data["courses"].first["course_no"]
  end

  test "combines query and filters" do
    result = call_tool(query: "2110", revision_year: 2565)
    data = JSON.parse(result)
    assert_equal 2, data["courses"].size
  end

  test "no results when filters don't match" do
    result = call_tool(program_code: "CM")
    data = JSON.parse(result)
    assert_equal 0, data["courses"].size
  end

  # --- Multiple revisions of the same course ---

  test "orders same course_no by newest revision first" do
    c = Course.create!(course_no: "2110101", name: "Introduction to Computing",
                       revision_year_be: 2566)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: c)

    result = call_tool(query: "2110101")
    data = JSON.parse(result)
    assert_equal 2, data["courses"].size
    assert_equal [2566, 2565], data["courses"].map { |c| c["revision_year"] }
  end

  # --- count_only ---

  test "count_only returns count and filters" do
    result = call_tool(program_code: "CP", count_only: true)
    data = JSON.parse(result)
    assert_equal 3, data["count"]
    assert_match(/program=CP/, data["filters"])
    assert_not data.key?("courses")
  end

  # --- limit ---

  test "respects limit parameter" do
    result = call_tool(program_code: "CP", limit: 2)
    data = JSON.parse(result)
    assert_equal 2, data["courses"].size
    assert_equal 3, data["total"]
    assert_match(/Showing 2 of 3/, data["note"])
  end

  test "limit is clamped to MAX_LIMIT" do
    result = call_tool(program_code: "CP", limit: 100)
    data = JSON.parse(result)
    assert data["courses"].size <= Line::Tools::CourseLookupTool::MAX_LIMIT
  end

  # --- Serialization ---

  test "serialized course has expected fields" do
    result = call_tool(query: "2110101")
    course = JSON.parse(result)["courses"].first

    assert_equal "2110101", course["course_no"]
    assert_equal "Introduction to Computing", course["name_en"]
    assert_equal "วิทยาการคำนวณเบื้องต้น", course["name_th"]
    assert_equal 3, course["credits"]
    assert_equal 2565, course["revision_year"]
    assert_equal "CP (2540)", course["program"]
    assert_equal false, course["is_gened"]
    assert_equal false, course["is_thesis"]
  end

  # --- No arguments ---

  test "returns all courses when no arguments given" do
    result = call_tool
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  private

  def call_tool(**args)
    Line::Tools::CourseLookupTool.call(args.stringify_keys)
  end
end
