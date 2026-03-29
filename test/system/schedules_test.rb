require "application_system_test_case"

class SchedulesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "landing page shows report cards" do
    visit schedules_path
    assert_text "Schedules"
    assert_text "Room Schedule"
    assert_text "Staff Schedule"
    assert_text "Curriculum Calendar"
    assert_text "Student Timetable"
    assert_text "Staff Workload"
    assert_text "Conflict Detection"
  end

  test "room schedule shows calendar for room and semester" do
    visit schedules_room_path

    select2_pick semester_label(semesters(:sem_2568_1)), from: "Semester"
    select2_pick rooms(:eng4_303).display_name, from: "Room"
    click_on "View"

    assert_text rooms(:eng4_303).display_name
    # Should show intro_computing time slots (Mon & Wed 09:00-10:30)
    assert_selector ".wc-block", minimum: 2
    assert_text courses(:intro_computing).course_no
  end

  test "staff schedule shows calendar for staff and semester" do
    visit schedules_staff_path

    select2_pick semester_label(semesters(:sem_2568_1)), from: "Semester"
    select2_pick staffs(:lecturer_smith).display_name_th, from: "Staff"
    click_on "View"

    assert_text staffs(:lecturer_smith).display_name_th
    assert_selector ".wc-block", minimum: 1
    assert_text "Load Summary"
  end

  test "curriculum calendar shows calendar for selected courses" do
    visit schedules_curriculum_path

    select2_pick semester_label(semesters(:sem_2568_1)), from: "Semester"
    # Multi-select course
    find_select2_container("Courses").find(".select2-selection").click
    find(".select2-dropdown .select2-results__option", text: courses(:intro_computing).course_no).click
    click_on "View"

    assert_selector ".wc-block", minimum: 1
    assert_text courses(:intro_computing).course_no
  end

  test "student timetable shows empty state when no schedule data" do
    visit schedules_student_path(semester_id: semesters(:sem_2568_1).id, student_id: students(:active_student).id)

    # Active student has grades in year 2024 but semester fixture is 2568 — no match expected
    assert_text "No grades found"
  end

  test "workload shows table with staff loads" do
    visit schedules_workload_path(start_year: 2568, end_year: 2568)

    assert_text "Staff Workload"
    # Smith teaches sec 1 (1.0) + sec 2 (0.5) = 1.5 total
    assert_text staffs(:lecturer_smith).display_name_th
    assert_text "1.5"
  end

  test "conflicts page shows no conflicts message" do
    visit schedules_conflicts_path(semester_id: semesters(:sem_2568_1).id)

    assert_text "Conflict Detection"
    # Fixture data has no overlapping time slots in the same room
    assert_text "No conflicts" # badge or message
  end

  private

  def semester_label(semester)
    "#{semester.display_name} — #{Semester::SEMESTER_LABELS[semester.semester_number]}"
  end

  def find_select2_container(label_text)
    label = find("label", text: label_text)
    container = label.ancestor(".col-md-3, .col-md-4, .col-md-7", match: :first)
    container.find(".select2-container")
  end

  def select2_pick(value, from:)
    container = find_select2_container(from)
    container.find(".select2-selection").click
    find(".select2-dropdown .select2-results__option", text: value).click
  end
end
