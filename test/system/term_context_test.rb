require "application_system_test_case"

class TermContextTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  # Each test changes only the YEAR dropdown — one submit-on-change per interaction —
  # and waits for the reload (the bar showing the new year selected) before navigating,
  # so there is no race between the auto-submit and the next step.

  test "setting the term pre-fills a consuming report" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"
    visit report_path("failing_students")
    assert_selector "input#year[value='2567']"
  end

  test "changing the term on a report does not change the sticky setting" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"

    # Override the year on one report's own form (do not submit it anywhere sticky).
    visit report_path("failing_students")
    fill_in "year", with: "2568"

    # A different consuming report still reflects the sticky 2567, not the override.
    visit report_path("semester_grade_distribution")
    assert_selector "input#year[value='2567']"
  end

  test "a range report ignores the sticky term" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"
    visit schedules_workload_path
    assert_no_selector ".term-context-bar"
  end
end
