require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  def login_as(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "signing in lands on the launchpad" do
    login_as users(:viewer)

    assert_current_path root_path
    # Band headings are uppercased by CSS, so Selenium reads them uppercase.
    assert_selector "h6", text: /\ARecords\z/i
    assert_selector "h6", text: /\AReports\z/i
    assert_link "Students"
  end

  test "a report on the launchpad opens that report" do
    login_as users(:viewer)

    # Scope to main: the sidebar links some of the same destinations, and an
    # unscoped click_on raises Capybara::Ambiguous.
    within("main") { click_on "Teaching Matrix" }
    assert_current_path schedules_teaching_matrix_path
  end

  test "an entity area on the launchpad opens that area" do
    login_as users(:viewer)

    within("main") { click_on "Semesters" }
    assert_current_path semesters_path
  end

  test "a non-admin sees no Users link in the sidebar" do
    login_as users(:viewer)

    assert_no_selector "nav#sidebar a", text: "Users"
    assert_selector "nav#sidebar a", text: "Students"
  end

  test "an admin sees Users in the sidebar admin block" do
    login_as users(:admin)

    assert_selector "nav#sidebar a", text: "Users"
  end
end
