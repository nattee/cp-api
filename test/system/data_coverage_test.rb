require "application_system_test_case"

class DataCoverageTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "coverage report renders the matrix with flagged cells" do
    sign_in users(:admin)
    visit report_path("data_coverage")
    click_on "Run report"

    assert_text "2567/1"          # fixture grades live at year_ce 2024
    assert_text(/Grades/i)
    # Fixture semesters 2568/1 + 2568/2 exist with zero grades -> red cells
    # inside the grades era.
    assert_selector "td.report-cell-missing"
  end

  test "program-courses-only checkbox round-trips" do
    sign_in users(:admin)
    visit report_path("data_coverage")
    check "program_courses_only"
    click_on "Run report"

    assert_selector "input#program_courses_only[checked]"
    assert_text "2567/1"
  end

  test "appears on the reports index under Data" do
    sign_in users(:admin)
    visit reports_path

    assert_text "Data"
    assert_text "Which terms are missing data"
  end
end
