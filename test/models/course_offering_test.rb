require "test_helper"

class CourseOfferingTest < ActiveSupport::TestCase
  test "valid with course, semester, and status" do
    offering = CourseOffering.new(
      course: courses(:gened_course),
      semester: semesters(:sem_2568_1),
      status: "planned"
    )
    assert offering.valid?
  end

  test "requires course" do
    offering = CourseOffering.new(
      course: nil,
      semester: semesters(:sem_2568_1),
      status: "planned"
    )
    assert_not offering.valid?
    assert_includes offering.errors[:course], "must exist"
  end

  test "requires semester" do
    offering = CourseOffering.new(
      course: courses(:intro_computing),
      semester: nil,
      status: "planned"
    )
    assert_not offering.valid?
    assert_includes offering.errors[:semester], "must exist"
  end

  test "status defaults to planned" do
    offering = CourseOffering.new(
      course: courses(:gened_course),
      semester: semesters(:sem_2568_1)
    )
    assert_equal "planned", offering.status
  end

  test "status must be in STATUSES" do
    offering = CourseOffering.new(
      course: courses(:gened_course),
      semester: semesters(:sem_2568_1),
      status: "invalid"
    )
    assert_not offering.valid?
    assert_includes offering.errors[:status], "is not included in the list"
  end

  test "unique on course_id and semester_id" do
    existing = course_offerings(:intro_computing_2568_1)
    offering = CourseOffering.new(
      course: existing.course,
      semester: existing.semester,
      status: "planned"
    )
    assert_not offering.valid?
    assert_includes offering.errors[:course_id], "is already offered in this semester"
  end

  test "destroys sections on delete" do
    offering = course_offerings(:intro_computing_2568_1)
    section_ids = offering.sections.pluck(:id)
    assert section_ids.any?
    offering.destroy
    assert_empty Section.where(id: section_ids)
  end
end
