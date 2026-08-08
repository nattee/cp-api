require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { username: user.username, password: "password123" }
  end

  test "a non-admin lecturer can open the reports hub" do
    login users(:viewer)
    get reports_path
    assert_response :success
  end

  test "a non-admin lecturer can open a registry hub report" do
    login users(:viewer)
    get report_path("failing_students")
    assert_response :success
  end

  test "a non-admin cannot open the admin-only data coverage report" do
    login users(:viewer)
    get report_path("data_coverage")
    assert_redirected_to root_path
  end

  test "an admin can open the data coverage report" do
    login users(:admin)
    get report_path("data_coverage")
    assert_response :success
  end

  test "an unknown report key redirects back to the hub" do
    login users(:viewer)
    get report_path("no_such_report")
    assert_redirected_to reports_path
  end

  test "an external report key redirects to that report's own page" do
    login users(:viewer)
    get report_path("schedules_room")
    assert_redirected_to schedules_room_path
  end

  test "the program filter narrows the hub to applicable reports" do
    login users(:viewer)
    get reports_path, params: { program_group: "CP" }
    assert_response :success
    # Thesis Credits is master-only; CP is a bachelor group, so its card is hidden.
    assert_select "a.card .card-title", text: "Thesis credits per student", count: 0
    # A program-agnostic schedules card is still present.
    assert_select "a.card .card-title", text: "Room Schedule"
  end

  test "a viewing-year field pre-fills from the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("semester_grade_distribution")
    assert_select "input#year[value=?]", "2567"
    assert_select "select#term option[selected][value=?]", "1"
  end

  test "an explicit param overrides the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("semester_grade_distribution"), params: { year: 2568 }
    assert_select "input#year[value=?]", "2568"
  end

  test "a cohort report's admission_year is never filled from the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("cohort_gpa")
    # admission_year must NOT be pre-filled with the context year
    assert_select "input#admission_year[value=?]", "2567", count: 0
  end

  # --- CSV export honours required-param validation ---
  # A bare `.csv` request must not execute a report with blank required params
  # (the CSV branch runs the report directly, bypassing the HTML run gate).

  test "csv export redirects when required params are blank" do
    login users(:viewer)
    get report_path("failing_students", format: :csv)
    assert_redirected_to report_path("failing_students")
  end

  test "csv export runs when required params are present" do
    login users(:viewer)
    get report_path("failing_students", format: :csv), params: { course_no: "2110101", year: 2567 }
    assert_response :success
    assert_equal "text/csv", response.media_type
  end
end
