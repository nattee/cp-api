require "test_helper"

class TermContextBarTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { username: users(:viewer).username, password: "password123" } }

  test "the bar appears on the reports hub" do
    get reports_path
    assert_select ".term-context-bar"
  end

  test "the bar appears on a report that consumes the term" do
    get report_path("semester_grade_distribution")
    assert_select ".term-context-bar"
  end

  test "the bar is absent from a cohort report that ignores the term" do
    get report_path("cohort_gpa")
    assert_select ".term-context-bar", count: 0
  end

  test "the bar appears on the schedule calendars" do
    get schedules_room_path
    assert_select ".term-context-bar"
    get schedules_teaching_matrix_path
    assert_select ".term-context-bar"
  end

  test "the bar is absent from the workload range report" do
    get schedules_workload_path
    assert_select ".term-context-bar", count: 0
  end

  test "the bar shows the resolved default term" do
    get reports_path
    # default over fixtures is 2568 / semester 2
    assert_select ".term-context-bar select#year_be option[selected][value=?]", "2568"
    assert_select ".term-context-bar select#semester option[selected][value=?]", "2"
  end
end
