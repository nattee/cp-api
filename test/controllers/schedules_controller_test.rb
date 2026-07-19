require "test_helper"

class SchedulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "index redirects to the reports hub" do
    get schedules_path
    assert_redirected_to reports_path
  end

  test "room report is accessible" do
    get schedules_room_path
    assert_response :success
  end

  test "room report with filters" do
    get schedules_room_path, params: { semester_id: semesters(:sem_2568_1).id, room_id: rooms(:eng4_303).id }
    assert_response :success
  end

  test "staff report is accessible" do
    get schedules_staff_path
    assert_response :success
  end

  test "staff report with filters" do
    get schedules_staff_path, params: { semester_id: semesters(:sem_2568_1).id, staff_id: staffs(:lecturer_smith).id }
    assert_response :success
  end

  test "curriculum report is accessible" do
    get schedules_curriculum_path
    assert_response :success
  end

  test "curriculum report with filters" do
    get schedules_curriculum_path, params: { semester_id: semesters(:sem_2568_1).id, course_ids: [courses(:intro_computing).id] }
    assert_response :success
  end

  test "student report is accessible" do
    get schedules_student_path
    assert_response :success
  end

  test "student report with filters" do
    get schedules_student_path, params: { semester_id: semesters(:sem_2568_1).id, student_id: students(:active_student).id }
    assert_response :success
  end

  test "workload report is accessible" do
    get schedules_workload_path
    assert_response :success
  end

  test "workload report with year range" do
    get schedules_workload_path, params: { start_year: 2568, end_year: 2568 }
    assert_response :success
  end

  test "workload report with staff type filter" do
    get schedules_workload_path, params: { start_year: 2568, end_year: 2568, staff_type: "lecturer" }
    assert_response :success
  end

  test "conflicts report is accessible" do
    get schedules_conflicts_path
    assert_response :success
  end

  test "conflicts report with semester" do
    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id }
    assert_response :success
  end

  test "conflicts report with type filter" do
    get schedules_conflicts_path, params: { semester_id: semesters(:sem_2568_1).id, conflict_type: "room" }
    assert_response :success
  end

  test "teaching matrix defaults to the latest year with teachings" do
    get schedules_teaching_matrix_path
    assert_response :success
    assert_select "input#year[value=?]", "2568"
  end

  test "teaching matrix counts distinct sections per staff per course" do
    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1 }
    assert_response :success
    doc = Nokogiri::HTML(response.body)
    smith_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_smith).display_name_th) }
    assert smith_row, "smith row missing"
    # Dept scope (default): only 2110101 (sections 1 + 33) counts; column cell 2, total 2.
    assert_equal ["2", "2"], smith_row.css("td")[1..].map { |td| td.text.strip }
    # Jones only teaches the non-department gened course in 2567 → no row at all.
    assert_nil doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_jones).display_name_th) }
  end

  test "teaching matrix course scope toggles non-department columns" do
    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1 }
    assert_select "thead th a", text: "2103106", count: 0

    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1, course_scope: "all" }
    assert_select "thead th a", text: "2103106"
    doc = Nokogiri::HTML(response.body)
    jones_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_jones).display_name_th) }
    assert jones_row, "jones row missing in all-courses scope"
  end

  test "teaching matrix whole-year scope sums semesters and qualifies tooltips" do
    get schedules_teaching_matrix_path, params: { year: 2567 }
    assert_response :success
    doc = Nokogiri::HTML(response.body)
    smith_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_smith).display_name_th) }
    assert smith_row, "smith row missing"
    # 2 sections in 2567/1 + 1 in 2567/2 = 3, and 3 total.
    assert_equal ["3", "3"], smith_row.css("td")[1..].map { |td| td.text.strip }
    tooltip = smith_row.css("td[data-tooltip]").first["data-tooltip"]
    assert_includes tooltip, "2567/1: sec 1, 33"
    assert_includes tooltip, "2567/2: sec 2"
  end

  test "teaching matrix with no data shows the empty state" do
    get schedules_teaching_matrix_path, params: { year: 2500 }
    assert_response :success
    assert_match(/No teaching data/, response.body)
  end
end
