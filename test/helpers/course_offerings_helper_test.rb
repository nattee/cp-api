require "test_helper"

class CourseOfferingsHelperTest < ActionView::TestCase
  test "staff_short_name prefers initials, falls back to Thai display name" do
    assert_equal "JS", staff_short_name(staffs(:lecturer_smith))
    staff = Staff.new(first_name: "Anon", last_name: "Ymous",
                      first_name_th: "อานนท์", last_name_th: "ไอมัส", academic_title: "อ.")
    assert_equal "อ.อานนท์ ไอมัส", staff_short_name(staff)
  end

  test "section_schedule_summary collapses same time and room across days" do
    assert_equal "Mon/Wed 09:00-10:30 ENG4-303", section_schedule_summary(sections(:intro_sec_1))
  end

  test "section_schedule_summary splits differing rooms and renders TBA" do
    section = Section.new(section_number: 9)
    section.time_slots.build(day_of_week: 1, start_time: "09:00", end_time: "10:30", room: rooms(:eng4_303))
    section.time_slots.build(day_of_week: 3, start_time: "09:00", end_time: "10:30")
    assert_equal "Mon 09:00-10:30 ENG4-303; Wed 09:00-10:30 TBA", section_schedule_summary(section)
  end

  test "section_schedule_summary is nil without slots" do
    assert_nil section_schedule_summary(sections(:senior_sec_1))
  end

  test "section_enrollment_summary handles full, partial, and missing data" do
    assert_equal "45/50", section_enrollment_summary(Section.new(enrollment_current: 45, enrollment_max: 50))
    assert_equal "45/?", section_enrollment_summary(Section.new(enrollment_current: 45))
    assert_equal "?/50", section_enrollment_summary(Section.new(enrollment_max: 50))
    assert_nil section_enrollment_summary(Section.new)
  end
end
