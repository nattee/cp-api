require "application_system_test_case"

class ReportsHubTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "hub shows the four lecturer sections with cards" do
    sign_in users(:viewer)
    visit reports_path

    # Section headers render through Bootstrap's `.text-uppercase` utility
    # (app/views/reports/index.html.haml), so Selenium's rendered text is
    # visually uppercased even though the underlying label is mixed-case
    # (Reports::Catalog::SECTIONS) — match case-insensitively, same as the
    # GPA avg column in grade_reports_test.rb.
    assert_text(/Schedules/i)
    assert_text(/Teaching/i)
    assert_text(/Grades & Courses/i)
    assert_text(/Students & Cohorts/i)

    assert_link "Room Schedule"
    assert_link "Staff Workload"
    assert_link "Class Grade Distribution"
    assert_link "Cohort GPA by semester"
  end

  test "data coverage does not appear on the hub" do
    sign_in users(:admin)
    visit reports_path
    assert_no_text "Which terms are missing data"
  end

  test "a schedules card navigates to its report" do
    sign_in users(:viewer)
    visit reports_path
    click_on "Room Schedule"
    assert_current_path schedules_room_path
  end

  test "sidebar shows one Reports item and no separate Schedules item for a lecturer" do
    sign_in users(:viewer)
    visit reports_path
    within "#sidebar" do
      assert_link "Reports"
      assert_no_link "Schedules"
    end
  end
end
