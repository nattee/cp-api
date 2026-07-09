require "application_system_test_case"

class GradeReportsTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "semester grade distribution: form -> chart + table" do
    sign_in users(:admin)
    visit report_path("semester_grade_distribution")

    select "CP", from: "program_group"
    fill_in "year", with: "2567"          # B.E. of the 2024 fixture grades
    select "First", from: "term"
    click_on "Run report"

    assert_text "2110101"                 # intro_computing row (grade A fixture)
    assert_text "GPA"
    assert_selector "canvas"              # the horizontal stacked-bar chart
  end

  test "cohort GPA: form -> chart + table with B.E. term labels" do
    sign_in users(:admin)
    visit report_path("cohort_gpa")

    select "CP", from: "program_group"
    fill_in "admission_year", with: "2567" # active_student's cohort
    click_on "Run report"

    assert_text "2567/1"                  # year_ce 2024 + 543
    # Table headers render inside .card, where a global rule
    # (`.card .table > thead > tr > th { text-transform: uppercase; }` in
    # application.scss) visually uppercases them. Selenium's rendered text
    # reflects that CSS transform ("GPS AVG"), so match case-insensitively —
    # the underlying column label is still "GPS avg" (Reports::CohortGpa).
    assert_text(/GPS avg/i)
    assert_selector "canvas"              # the GPA trend chart
  end

  test "both reports appear on the reports index" do
    sign_in users(:admin)
    visit reports_path

    assert_text "Grade distribution by course"
    assert_text "Cohort GPA by semester"
  end
end
