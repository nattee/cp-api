require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { username: user.username, password: "password123" }
  end

  test "root renders the launchpad for a non-admin" do
    login users(:viewer)
    get root_path
    assert_response :success
    assert_select "h6", text: /\ARecords\z/i, count: 1
  end

  test "root requires login" do
    get root_path
    assert_redirected_to login_path
  end

  test "the launchpad links every non-admin area" do
    login users(:viewer)
    get root_path
    assert_select "a[href=?]", students_path
    assert_select "a[href=?]", semesters_path
    assert_select "a[href=?]", line_account_path
  end

  test "the administration band is admin-only" do
    login users(:viewer)
    get root_path
    assert_select "h6", text: /\AAdministration\z/i, count: 0
    assert_select "a[href=?]", data_imports_path, count: 0

    login users(:admin)
    get root_path
    assert_select "h6", text: /\AAdministration\z/i
    assert_select "a[href=?]", data_imports_path
  end

  test "reports come from the catalog rather than a hardcoded list" do
    login users(:viewer)
    get root_path
    # One report from each of the four hub sections.
    assert_select "a[href=?]", schedules_room_path
    assert_select "a[href=?]", schedules_teaching_matrix_path
    assert_select "a[href=?]", report_path("failing_students")
    assert_select "a[href=?]", report_path("cohort_gpa")
  end

  test "the admin-only data coverage report is not listed on the launchpad" do
    login users(:admin)
    get root_path
    assert_select "a[href=?]", report_path("data_coverage"), count: 0
  end

  test "the reports band links to the hub itself" do
    login users(:viewer)
    get root_path
    assert_select "a[href=?]", reports_path
  end
end
