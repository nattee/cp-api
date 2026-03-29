require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "valid with building and room_number" do
    room = Room.new(building: "ENG3", room_number: "101")
    assert room.valid?
  end

  test "requires building" do
    room = rooms(:eng4_303).dup
    room.building = nil
    assert_not room.valid?
    assert_includes room.errors[:building], "can't be blank"
  end

  test "requires room_number" do
    room = rooms(:eng4_303).dup
    room.room_number = nil
    assert_not room.valid?
    assert_includes room.errors[:room_number], "can't be blank"
  end

  test "unique on building and room_number" do
    room = Room.new(
      building: rooms(:eng4_303).building,
      room_number: rooms(:eng4_303).room_number
    )
    assert_not room.valid?
    assert_includes room.errors[:room_number], "has already been taken"
  end

  test "room_type must be in ROOM_TYPES when present" do
    room = Room.new(building: "ENG3", room_number: "102", room_type: "invalid")
    assert_not room.valid?
    assert_includes room.errors[:room_type], "is not included in the list"
  end

  test "room_type allows nil" do
    room = Room.new(building: "ENG3", room_number: "102", room_type: nil)
    assert room.valid?
  end

  test "capacity must be positive integer when present" do
    room = Room.new(building: "ENG3", room_number: "102", capacity: 0)
    assert_not room.valid?
    assert_includes room.errors[:capacity], "must be greater than 0"
  end

  test "capacity allows nil" do
    room = Room.new(building: "ENG3", room_number: "102", capacity: nil)
    assert room.valid?
  end

  test "display_name returns building-room_number" do
    room = rooms(:eng4_303)
    assert_equal "ENG4-303", room.display_name
  end

  test "cannot delete room with associated time slots" do
    room = rooms(:eng4_303)
    assert_not room.destroy
    assert_includes room.errors[:base], "Cannot delete record because dependent time slots exist"
  end
end
