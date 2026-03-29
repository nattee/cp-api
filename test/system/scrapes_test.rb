require "application_system_test_case"

class ScrapesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index shows scrape history" do
    visit scrapes_path
    assert_text "Scrape History"
    assert_text "CuGetReg"
    assert_text "Completed"
  end

  test "show page displays scrape details" do
    visit scrape_path(scrapes(:completed_scrape))
    assert_text "CuGetReg"
    assert_text "Completed"
    assert_text scrapes(:completed_scrape).semester.display_name
  end

  test "show page auto-refreshes when running" do
    visit scrape_path(scrapes(:running_scrape))
    assert_text "Running"
    assert_text "Auto-refreshing"
    # Verify the meta refresh tag is present
    assert_selector "meta[http-equiv='refresh']", visible: false
  end
end
