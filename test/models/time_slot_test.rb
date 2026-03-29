require "test_helper"

class TimeSlotTest < ActiveSupport::TestCase
  test "valid with section, day_of_week, start_time, and end_time" do
    slot = TimeSlot.new(
      section: sections(:senior_sec_1),
      day_of_week: 1,
      start_time: "09:00",
      end_time: "10:30"
    )
    assert slot.valid?
  end

  test "requires day_of_week" do
    slot = time_slots(:intro_sec1_mon).dup
    slot.day_of_week = nil
    assert_not slot.valid?
    assert_includes slot.errors[:day_of_week], "can't be blank"
  end

  test "requires start_time" do
    slot = time_slots(:intro_sec1_mon).dup
    slot.start_time = nil
    assert_not slot.valid?
    assert_includes slot.errors[:start_time], "can't be blank"
  end

  test "requires end_time" do
    slot = time_slots(:intro_sec1_mon).dup
    slot.end_time = nil
    assert_not slot.valid?
    assert_includes slot.errors[:end_time], "can't be blank"
  end

  test "day_of_week must be 0-6" do
    slot = TimeSlot.new(
      section: sections(:senior_sec_1),
      day_of_week: 7,
      start_time: "09:00",
      end_time: "10:30"
    )
    assert_not slot.valid?
    assert_includes slot.errors[:day_of_week], "is not included in the list"
  end

  test "room is optional" do
    slot = TimeSlot.new(
      section: sections(:senior_sec_1),
      day_of_week: 4,
      start_time: "13:00",
      end_time: "14:30",
      room: nil
    )
    assert slot.valid?
  end

  test "end_time must be after start_time" do
    slot = TimeSlot.new(
      section: sections(:senior_sec_1),
      day_of_week: 1,
      start_time: "10:00",
      end_time: "09:00"
    )
    assert_not slot.valid?
    assert_includes slot.errors[:end_time], "must be after start time"
  end

  test "end_time equal to start_time is invalid" do
    slot = TimeSlot.new(
      section: sections(:senior_sec_1),
      day_of_week: 1,
      start_time: "10:00",
      end_time: "10:00"
    )
    assert_not slot.valid?
    assert_includes slot.errors[:end_time], "must be after start time"
  end

  test "day_name returns Monday for day_of_week 1" do
    slot = time_slots(:intro_sec1_mon)
    assert_equal "Monday", slot.day_name
  end

  test "time_range returns formatted range" do
    slot = time_slots(:intro_sec1_mon)
    assert_equal "09:00-10:30", slot.time_range
  end
end
