require "test_helper"

class SectionTest < ActiveSupport::TestCase
  test "valid with course_offering and section_number" do
    offering = course_offerings(:senior_project_2568_1)
    section = Section.new(course_offering: offering, section_number: 2)
    assert section.valid?
  end

  test "requires section_number" do
    section = sections(:intro_sec_1).dup
    section.section_number = nil
    assert_not section.valid?
    assert_includes section.errors[:section_number], "can't be blank"
  end

  test "section_number must be positive integer" do
    offering = course_offerings(:senior_project_2568_1)
    section = Section.new(course_offering: offering, section_number: 0)
    assert_not section.valid?
    assert_includes section.errors[:section_number], "must be greater than 0"
  end

  test "unique on course_offering_id and section_number" do
    existing = sections(:intro_sec_1)
    section = Section.new(
      course_offering: existing.course_offering,
      section_number: existing.section_number
    )
    assert_not section.valid?
    assert_includes section.errors[:section_number], "has already been taken"
  end

  test "destroys time_slots on delete" do
    section = sections(:intro_sec_1)
    slot_ids = section.time_slots.pluck(:id)
    assert slot_ids.any?
    section.destroy
    assert_empty TimeSlot.where(id: slot_ids)
  end

  test "destroys teachings on delete" do
    section = sections(:intro_sec_1)
    teaching_ids = section.teachings.pluck(:id)
    assert teaching_ids.any?
    section.destroy
    assert_empty Teaching.where(id: teaching_ids)
  end
end
