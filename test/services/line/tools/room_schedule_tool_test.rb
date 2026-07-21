require "test_helper"

class Line::Tools::RoomScheduleToolTest < ActiveSupport::TestCase
  # Fixtures: room eng4_303 hosts intro_sec_1 (2110101, 2568/1) Mon+Wed
  # 09:00-10:30, taught by lecturer_smith.

  test "returns weekly schedule for an exact room name" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      { "room" => "ENG4-303", "semester" => "2568/1" }))

    assert_equal "ENG4-303", result["room"]
    assert_equal "2568/1", result["semester"]
    assert_equal 2, result["entries"].size

    entry = result["entries"].first
    assert_equal "Monday", entry["day"]
    assert_equal "09:00-10:30", entry["time"]
    assert_equal "2110101", entry["course_no"]
    assert_equal 1, entry["section"]
    assert_includes entry["instructors"], "ผศ.ดร.จอห์น สมิธ"
  end

  test "day filter narrows entries" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      { "room" => "ENG4-303", "semester" => "2568/1", "day" => "Mon" }))

    assert_equal [ "Monday" ], result["entries"].map { |e| e["day"] }
  end

  test "ambiguous room query returns match list" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call({ "room" => "ENG4" }))

    assert_match(/Multiple rooms/, result["error"])
    assert_includes result["matches"], "ENG4-303"
  end

  test "unknown room returns error" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call({ "room" => "BLDG9-999" }))
    assert_match(/No room found/, result["error"])
  end

  test "unparseable day returns error" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      { "room" => "ENG4-303", "day" => "someday" }))
    assert_match(/Could not parse day/, result["error"])
  end

  test "room with no classes reports an empty schedule" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      { "room" => "ENG3-201", "semester" => "2568/1" }))

    assert_equal [], result["entries"]
    assert_match(/No classes/, result["note"])
  end

  test "capacity and room_type keys are always present, even when nil" do
    # No fixture room has a nil capacity/room_type -- create one in-test
    # (never edit fixtures) to prove the response no longer drops these keys
    # via a blanket .compact.
    Room.create!(building: "ENG9", room_number: "TBD", room_type: nil, capacity: nil)

    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      { "room" => "ENG9-TBD", "semester" => "2568/1" }))

    assert result.key?("capacity")
    assert_nil result["capacity"]
    assert result.key?("room_type")
    assert_nil result["room_type"]
  end
end
