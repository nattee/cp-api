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

  test "the program filter narrows the hub to applicable reports" do
    login users(:viewer)
    get reports_path, params: { program_group: "CP" }
    assert_response :success
    # Thesis Credits is master-only; CP is a bachelor group, so its card is hidden.
    assert_select "a.card .card-title", text: "Thesis credits per student", count: 0
    # A program-agnostic schedules card is still present.
    assert_select "a.card .card-title", text: "Room Schedule"
  end
end
