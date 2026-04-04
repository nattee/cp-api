require "test_helper"

class Line::Tools::StudentLookupToolTest < ActiveSupport::TestCase
  # Fixtures: active_student (6732100021, Thanawat Sricharoen, 2567, active, CP),
  #           graduated_student (6532100071, Arunee Phanomwan, 2565, graduated, CP),
  #           on_leave_student (6632100063, Kittipat Thongkham, 2566, on_leave, CP)

  # --- Search by student ID ---

  test "finds student by exact ID" do
    result = call_tool(query: "6732100021")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "finds students by partial ID prefix" do
    result = call_tool(query: "67321")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "returns empty for non-matching ID" do
    result = call_tool(query: "9999999999")
    data = JSON.parse(result)
    assert_equal 0, data["students"].size
  end

  # --- Search by name ---

  test "finds student by English first name" do
    result = call_tool(query: "Thanawat")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "finds student by English last name" do
    result = call_tool(query: "Phanomwan")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6532100071", data["students"].first["student_id"]
  end

  test "finds student by Thai name" do
    result = call_tool(query: "ธนวัฒน์")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "name search is case-insensitive partial match" do
    result = call_tool(query: "thanawat")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
  end

  # --- Filters ---

  test "filters by program_code" do
    result = call_tool(program_code: "CP")
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  test "filters by admission_year" do
    result = call_tool(admission_year: 2567)
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "filters by status" do
    result = call_tool(status: "graduated")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6532100071", data["students"].first["student_id"]
  end

  test "combines query and filters" do
    result = call_tool(program_code: "CP", status: "active")
    data = JSON.parse(result)
    assert_equal 1, data["students"].size
    assert_equal "6732100021", data["students"].first["student_id"]
  end

  test "no results when filters don't match" do
    result = call_tool(program_code: "CP", status: "retired")
    data = JSON.parse(result)
    assert_equal 0, data["students"].size
  end

  # --- count_only ---

  test "count_only returns count and filters" do
    result = call_tool(program_code: "CP", count_only: true)
    data = JSON.parse(result)
    assert_equal 3, data["count"]
    assert_match(/program=CP/, data["filters"])
    assert_not data.key?("students")
  end

  # --- limit ---

  test "respects limit parameter" do
    result = call_tool(program_code: "CP", limit: 2)
    data = JSON.parse(result)
    assert_equal 2, data["students"].size
    assert_equal 3, data["total"]
    assert_match(/Showing 2 of 3/, data["note"])
  end

  test "limit is clamped to MAX_LIMIT" do
    result = call_tool(program_code: "CP", limit: 100)
    data = JSON.parse(result)
    # Should work without error, clamped to 50
    assert data["students"].size <= Line::Tools::StudentLookupTool::MAX_LIMIT
  end

  # --- Serialization ---

  test "serialized student has expected fields" do
    result = call_tool(query: "6732100021")
    student = JSON.parse(result)["students"].first

    assert_equal "6732100021", student["student_id"]
    assert student["name_en"].present?
    assert student["program"].present?
    assert_equal "active", student["status"]
    assert_equal 2567, student["admission_year"]
  end

  # --- No arguments ---

  test "returns all students when no arguments given" do
    result = call_tool
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  private

  def call_tool(**args)
    Line::Tools::StudentLookupTool.call(args.stringify_keys)
  end
end
