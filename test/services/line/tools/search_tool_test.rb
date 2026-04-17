require "test_helper"

class Line::Tools::SearchToolTest < ActiveSupport::TestCase
  # Fixtures:
  #   Students: active_student (6732100021, Thanawat, ธนวัฒน์), graduated_student, on_leave_student
  #   Staff: lecturer_smith (JS, John, จอห์น), lecturer_jones (JJ, Jane), retired_staff (Bob Brown)
  #   Courses: intro_computing (2110101), senior_project (2110499), gened_course (2103106)

  # --- Cross-entity search by name ---

  test "finds staff by name" do
    result = call_tool(query: "John")
    data = JSON.parse(result)
    assert_operator data["staff_total"], :>=, 1
    assert data["staff"].any? { |s| s["name_en"].include?("John") }
  end

  test "finds student by name" do
    result = call_tool(query: "Thanawat")
    data = JSON.parse(result)
    assert_operator data["students_total"], :>=, 1
    assert data["students"].any? { |s| s["name_en"].include?("Thanawat") }
  end

  test "finds course by number" do
    result = call_tool(query: "2110101")
    data = JSON.parse(result)
    assert_operator data["courses_total"], :>=, 1
    assert data["courses"].any? { |c| c["course_no"] == "2110101" }
  end

  test "finds course by partial number" do
    result = call_tool(query: "2110")
    data = JSON.parse(result)
    assert_operator data["courses_total"], :>=, 2
  end

  test "finds course by name" do
    result = call_tool(query: "Computing")
    data = JSON.parse(result)
    assert_operator data["courses_total"], :>=, 1
    assert data["courses"].any? { |c| c["name"].include?("Computing") }
  end

  # --- Thai name search ---

  test "finds staff by Thai name" do
    result = call_tool(query: "จอห์น")
    data = JSON.parse(result)
    assert_operator data["staff_total"], :>=, 1
  end

  test "finds student by Thai name" do
    result = call_tool(query: "ธนวัฒน์")
    data = JSON.parse(result)
    assert_operator data["students_total"], :>=, 1
  end

  # --- Initials ---

  test "finds staff by initials" do
    result = call_tool(query: "JS")
    data = JSON.parse(result)
    assert_equal 1, data["staff_total"]
    assert_equal "JS", data["staff"].first["initials"]
  end

  # --- Student ID ---

  test "finds student by ID prefix" do
    result = call_tool(query: "6732100021")
    data = JSON.parse(result)
    assert_equal 1, data["students_total"]
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  # --- No results ---

  test "returns empty results for non-matching query" do
    result = call_tool(query: "zzzzzzzzz")
    data = JSON.parse(result)
    assert_equal 0, data["students_total"]
    assert_equal 0, data["staff_total"]
    assert_equal 0, data["courses_total"]
    assert_match(/0 student/, data["summary"])
  end

  # --- Required query ---

  test "returns error when query is blank" do
    result = call_tool(query: "")
    data = JSON.parse(result)
    assert data.key?("error")
  end

  # --- Summary ---

  test "summary describes match counts" do
    result = call_tool(query: "John")
    data = JSON.parse(result)
    assert_match(/staff/, data["summary"])
    assert_match(/student/, data["summary"])
    assert_match(/course/, data["summary"])
  end

  # --- Limit ---

  test "respects per-entity limit" do
    result = call_tool(query: "2", limit: 1)
    data = JSON.parse(result)
    # Even if more exist, each category returns at most 1
    assert data["students"].size <= 1
    assert data["staff"].size <= 1
    assert data["courses"].size <= 1
  end

  # --- Course deduplication ---

  test "courses are deduplicated across revision years" do
    # intro_computing has course_no 2110101 — only one revision in fixtures
    result = call_tool(query: "2110101")
    data = JSON.parse(result)
    course_nos = data["courses"].map { |c| c["course_no"] }
    assert_equal course_nos.uniq, course_nos
  end

  # --- Serialization ---

  test "student results have expected fields" do
    result = call_tool(query: "6732100021")
    student = JSON.parse(result)["students"].first
    assert student.key?("student_id")
    assert student.key?("name_th")
    assert student.key?("name_en")
    assert student.key?("program")
    assert student.key?("status")
  end

  test "staff results have expected fields" do
    result = call_tool(query: "JS")
    staff = JSON.parse(result)["staff"].first
    assert staff.key?("name_th")
    assert staff.key?("name_en")
    assert staff.key?("initials")
    assert staff.key?("staff_type")
    assert staff.key?("status")
  end

  test "course results have expected fields" do
    result = call_tool(query: "2110101")
    course = JSON.parse(result)["courses"].first
    assert course.key?("course_no")
    assert course.key?("name")
    assert course.key?("credits")
    assert course.key?("revision_year")
  end

  private

  def call_tool(**args)
    Line::Tools::SearchTool.call(args.stringify_keys)
  end
end
