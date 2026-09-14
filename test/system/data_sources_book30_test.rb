require "application_system_test_case"

class DataSourcesBook30Test < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "admin sees the empty state, then the ledger once entries exist" do
    sign_in users(:admin)
    visit data_sources_book30_path
    assert_text "No book entries yet"

    student = students(:active_student)
    Book30Entry.create!(cohort: "CP51", year_be: 2567, line_no: 1, raw_line: "นาย ทดสอบ นิสิต", outcome: "linked_exact", student: student)
    visit data_sources_book30_path
    assert_text "Cohort ledger"
    assert_text "CP51"
    assert_text "Confirmed"
    assert_text "Corrections made by the import"
    visit student_path(student)
    assert_text "30-Year Book"
  end

  test "non-admin is redirected" do
    sign_in users(:viewer)
    visit data_sources_book30_path
    assert_text "Only admins can perform this action."
  end
end
