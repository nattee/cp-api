require "test_helper"

class SchedulesWorkloadAndConflictsTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  # --- Workload query ---

  test "workload shows staff with correct totals" do
    get schedules_workload_path, params: { start_year: 2568, end_year: 2568 }
    assert_response :success

    # Smith: sec1 (1.0) + sec2 (0.5) = 1.5 total
    assert_match(/1\.5/, response.body)
    # Jones: sec2 (0.5)
    assert_match(/0\.5/, response.body)
  end

  test "workload filters by staff type excludes non-matching" do
    get schedules_workload_path, params: { start_year: 2568, end_year: 2568, staff_type: "adjunct" }
    assert_response :success

    # No adjunct staff have teachings — table should not contain staff names
    assert_no_match(/#{staffs(:lecturer_smith).display_name_th}/, response.body)
  end

  test "workload with empty year range shows no data" do
    get schedules_workload_path, params: { start_year: 2500, end_year: 2500 }
    assert_response :success
    assert_match(/No teaching data/, response.body)
  end

  # --- Conflict detection ---

  test "no conflicts with non-overlapping fixture data" do
    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id }
    assert_response :success
    assert_match(/No conflicts/, response.body)
  end

  test "room conflict filter only" do
    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id, conflict_type: "room" }
    assert_response :success
    assert_match(/No conflicts|No scheduling conflicts/, response.body)
  end

  test "detects room conflict with overlapping slots" do
    # Create a conflicting slot: same room (eng4_303), same day (Monday), overlapping time
    TimeSlot.create!(
      section: sections(:senior_sec_1),
      room: rooms(:eng4_303),
      day_of_week: 1,
      start_time: "09:30",
      end_time: "11:00"
    )

    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id, conflict_type: "room" }
    assert_response :success
    assert_match(/ENG4-303/, response.body)
    assert_match(/Room/, response.body)
    # Should show both course numbers
    assert_match(/2110101/, response.body)
    assert_match(/2110499/, response.body)
  end

  test "does not flag adjacent non-overlapping slots as room conflicts" do
    # 09:00-10:00 then 10:00-11:00 in same room on Thursday — NOT overlapping
    TimeSlot.create!(section: sections(:senior_sec_1), room: rooms(:eng4_lab1), day_of_week: 4, start_time: "09:00", end_time: "10:00")
    TimeSlot.create!(section: sections(:intro_sec_1), room: rooms(:eng4_lab1), day_of_week: 4, start_time: "10:00", end_time: "11:00")

    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id, conflict_type: "room" }
    assert_response :success
    # Should NOT find Thursday conflicts for ENG4-LAB1
    assert_no_match(/Thursday.*ENG4-LAB1/, response.body)
  end

  test "detects staff conflict when teaching overlapping sections" do
    # Smith teaches sec1 (Mon 09:00-10:30) and sec2 (Tue 13:00-14:30)
    # Add Monday overlap to sec2
    TimeSlot.create!(
      section: sections(:intro_sec_2),
      room: rooms(:eng4_lab1),
      day_of_week: 1,
      start_time: "10:00",
      end_time: "11:30"
    )

    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id, conflict_type: "staff" }
    assert_response :success
    assert_match(/Staff/, response.body)
    assert_match(/#{Regexp.escape(staffs(:lecturer_smith).display_name_th)}/, response.body)
  end
end
