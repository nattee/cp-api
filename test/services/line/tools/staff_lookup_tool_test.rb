require "test_helper"

class Line::Tools::StaffLookupToolTest < ActiveSupport::TestCase
  # Fixtures: lecturer_smith (JS, active, ผศ.ดร. John Smith / จอห์น สมิธ),
  #           lecturer_jones (JJ, active, รศ.ดร. Jane Jones / เจน โจนส์),
  #           retired_staff (Bob Brown, retired, no initials, no Thai name)

  # --- Search by name ---

  test "finds staff by English first name" do
    result = call_tool(query: "John")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
    assert_equal "ผศ.ดร. John Smith", data["staff"].first["name_en"]
  end

  test "finds staff by English last name" do
    result = call_tool(query: "Jones")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
    assert_match(/Jones/, data["staff"].first["name_en"])
  end

  test "finds staff by Thai name" do
    result = call_tool(query: "จอห์น")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
    assert_match(/จอห์น/, data["staff"].first["name_th"])
  end

  test "finds staff by academic title" do
    result = call_tool(query: "รศ.ดร.")
    data = JSON.parse(result)
    assert data["staff"].any? { |s| s["name_en"].include?("Jones") }
  end

  test "name search is case-insensitive partial match" do
    result = call_tool(query: "smith")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
  end

  # --- Search by initials ---

  test "finds staff by exact initials" do
    result = call_tool(query: "JS")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
    assert_equal "JS", data["staff"].first["initials"]
  end

  test "initials search is exact match only" do
    result = call_tool(query: "JX")
    data = JSON.parse(result)
    assert_equal 0, data["staff"].size
  end

  # --- Filters ---

  test "filters by staff_type" do
    result = call_tool(staff_type: "lecturer")
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  test "filters by status" do
    result = call_tool(status: "retired")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
    assert_equal "retired", data["staff"].first["status"]
  end

  test "combines query and filters" do
    result = call_tool(query: "John", status: "active")
    data = JSON.parse(result)
    assert_equal 1, data["staff"].size
  end

  test "no results when filters don't match" do
    result = call_tool(query: "John", status: "retired")
    data = JSON.parse(result)
    assert_equal 0, data["staff"].size
  end

  # --- count_only ---

  test "count_only returns count and filters" do
    result = call_tool(status: "active", count_only: true)
    data = JSON.parse(result)
    assert_equal 2, data["count"]
    assert_match(/status=active/, data["filters"])
    assert_not data.key?("staff")
  end

  # --- limit ---

  test "respects limit parameter" do
    result = call_tool(staff_type: "lecturer", limit: 2)
    data = JSON.parse(result)
    assert_equal 2, data["staff"].size
    assert_equal 3, data["total"]
    assert_match(/Showing 2 of 3/, data["note"])
  end

  # --- Serialization ---

  test "serialized staff has expected fields" do
    result = call_tool(query: "JS")
    staff = JSON.parse(result)["staff"].first

    assert_equal "JS", staff["initials"]
    assert staff["name_en"].present?
    assert staff["name_th"].present?
    assert_equal "lecturer", staff["staff_type"]
    assert_equal "active", staff["status"]
    assert_kind_of Array, staff["programs"]
  end

  # --- No arguments ---

  test "returns all staff when no arguments given" do
    result = call_tool
    data = JSON.parse(result)
    assert_equal 3, data["total"]
  end

  # --- Teaching summary ---

  test "includes per-semester teaching summary with load totals" do
    result = JSON.parse(Line::Tools::StaffLookupTool.call({ "query" => "JS" }))
    teaching = result["staff"].first["teaching"]

    # lecturer_smith fixtures: 2568/1 → intro_sec_1 (1.0) + intro_sec_2 (0.5);
    # 2567/2 → 1 section; 2567/1 → 2 sections.
    assert_equal [ "2568/1", "2567/2", "2567/1" ], teaching.map { |t| t["semester"] }

    latest = teaching.first
    assert_equal 2, latest["section_count"]
    assert_in_delta 1.5, latest["total_load"], 0.001
    assert_includes latest["sections"], "2110101 Sec 1"
  end

  test "staff with no teachings gets an empty teaching list" do
    result = JSON.parse(Line::Tools::StaffLookupTool.call({ "query" => "Brown" }))
    assert_equal [], result["staff"].first["teaching"]
  end

  private

  def call_tool(**args)
    Line::Tools::StaffLookupTool.call(args.stringify_keys)
  end
end
