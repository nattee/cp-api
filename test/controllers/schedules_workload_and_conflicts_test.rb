require "test_helper"

class SchedulesWorkloadAndConflictsTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  # --- Workload matrix ---
  # Fixtures: Smith co-teaches intro_sec_1 (load 1.0) and intro_sec_2 (load 0.5);
  # Jones teaches intro_sec_2 (load 0.5). Both sections are course 2110101
  # (intro_computing: 3 credits, 3 contact hours) in semester 2568/1.
  # senior_sec_1 has no teaching assigned, so it contributes to no one.

  test "workload weights metrics by load_ratio and collapses sections of one course" do
    doc = get_workload(start_year: 2568, end_year: 2568)
    cell = first_cell(doc, staffs(:lecturer_smith))

    # 2 sections, but both are course 2110101 -> 1 distinct course (prep load).
    assert_equal "2", cell["data-sections"]
    assert_equal "1", cell["data-courses"]
    # credits = 3*1.0 + 3*0.5 = 4.5 ; contact hours = (3+0)*1.0 + (3+0)*0.5 = 4.5
    assert_equal "4.5", cell["data-credits"]
    assert_equal "4.5", cell["data-hours"]
  end

  test "workload gives a co-teacher only their split share" do
    doc = get_workload(start_year: 2568, end_year: 2568)
    cell = first_cell(doc, staffs(:lecturer_jones))

    assert_equal "1", cell["data-sections"]
    assert_equal "1.5", cell["data-credits"] # 3 * 0.5
    assert_equal "1.5", cell["data-hours"]
  end

  test "workload totals sum each metric across the range" do
    doc = get_workload(start_year: 2568, end_year: 2568)

    assert_equal "4.5", total(doc, staffs(:lecturer_smith), "credits")
    assert_equal "2",   total(doc, staffs(:lecturer_smith), "sections")
    assert_equal "1",   total(doc, staffs(:lecturer_smith), "courses")
    assert_equal "4.5", total(doc, staffs(:lecturer_smith), "hours")
  end

  test "workload orders staff by credits descending" do
    doc = get_workload(start_year: 2568, end_year: 2568)
    names = doc.css("table tbody tr td:first-child a").map(&:text)
    assert_equal [staffs(:lecturer_smith).display_name_th, staffs(:lecturer_jones).display_name_th], names
  end

  test "workload excludes staff with no teaching" do
    doc = get_workload(start_year: 2568, end_year: 2568)
    assert_nil staff_row(doc, staffs(:retired_staff)),
               "retired_staff has no teachings and should not appear in the matrix"
  end

  test "workload filters by staff type excludes non-matching" do
    get schedules_workload_path, params: { start_year: 2568, end_year: 2568, staff_type: "adjunct" }
    assert_response :success

    # No adjunct staff have teachings — table should not contain staff names
    assert_no_match(/#{Regexp.escape(staffs(:lecturer_smith).display_name_th)}/, response.body)
  end

  test "workload with empty year range shows no data" do
    get schedules_workload_path, params: { start_year: 2500, end_year: 2500 }
    assert_response :success
    assert_match(/No teaching data/, response.body)
  end

  test "workload defaults to a multi-year range ending at the latest semester" do
    get schedules_workload_path
    assert_response :success

    # Latest fixture semester is 2568; default end_year is the latest year.
    assert_select "input#end_year[value=?]", "2568"
    assert_select "table thead th", text: "2568/1"
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

  private

  def get_workload(**params)
    get schedules_workload_path, params: params
    assert_response :success
    Nokogiri::HTML(response.body)
  end

  # The <tr> whose first-column link points at this staff's show page, or nil.
  def staff_row(doc, staff)
    doc.css("table tbody tr").find do |tr|
      tr.at_css("td:first-child a")&.attr("href") == staff_path(staff)
    end
  end

  # First semester cell for a staff's row (semesters render oldest-first).
  def first_cell(doc, staff)
    row = staff_row(doc, staff)
    assert_not_nil row, "expected a workload row for #{staff.display_name_th}"
    row.at_css("td[data-wl-cell]")
  end

  # The rendered Σ total for one metric in a staff's row.
  def total(doc, staff, metric)
    row = staff_row(doc, staff)
    assert_not_nil row, "expected a workload row for #{staff.display_name_th}"
    row.at_css("td[data-wl-total='#{metric}'] strong").text
  end
end
