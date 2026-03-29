require "test_helper"

class TeachingTest < ActiveSupport::TestCase
  test "valid with section, staff, and load_ratio" do
    teaching = Teaching.new(
      section: sections(:senior_sec_1),
      staff: staffs(:lecturer_smith),
      load_ratio: 1.0
    )
    assert teaching.valid?
  end

  test "requires load_ratio" do
    teaching = teachings(:smith_intro_sec1).dup
    teaching.load_ratio = nil
    assert_not teaching.valid?
    assert_includes teaching.errors[:load_ratio], "can't be blank"
  end

  test "load_ratio must be greater than 0" do
    teaching = Teaching.new(
      section: sections(:senior_sec_1),
      staff: staffs(:lecturer_smith),
      load_ratio: 0
    )
    assert_not teaching.valid?
    assert_includes teaching.errors[:load_ratio], "must be greater than 0"
  end

  test "load_ratio must be less than or equal to 1" do
    teaching = Teaching.new(
      section: sections(:senior_sec_1),
      staff: staffs(:lecturer_smith),
      load_ratio: 1.5
    )
    assert_not teaching.valid?
    assert_includes teaching.errors[:load_ratio], "must be less than or equal to 1"
  end

  test "unique on section_id and staff_id" do
    existing = teachings(:smith_intro_sec1)
    teaching = Teaching.new(
      section: existing.section,
      staff: existing.staff,
      load_ratio: 0.5
    )
    assert_not teaching.valid?
    assert_includes teaching.errors[:staff_id], "has already been taken"
  end

  test "cannot delete staff with associated teachings" do
    staff = staffs(:lecturer_smith)
    assert_not staff.destroy
    assert_includes staff.errors[:base], "Cannot delete record because dependent teachings exist"
  end
end
