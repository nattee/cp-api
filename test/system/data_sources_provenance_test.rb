require "application_system_test_case"

class DataSourcesProvenanceTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "admin sees students by source and the import runs" do
    sign_in users(:admin)
    visit data_sources_provenance_path
    assert_text "Where the Data Came From"
    assert_text "Students by source"
    assert_text "Import runs"
    visit data_sources_path
    assert_link "Where the data came from"
  end

  test "non-admin is redirected" do
    sign_in users(:viewer)
    visit data_sources_provenance_path
    assert_text "Only admins can perform this action."
  end
end
