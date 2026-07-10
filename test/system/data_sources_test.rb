require "application_system_test_case"

class DataSourcesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "page lists every data source" do
    visit data_sources_path
    assert_text "CSV / Excel Imports"
    assert_text "ChulaBooster"
    assert_text "CuGetReg"
    assert_text "reg.chula (CAS Reg)"
  end

  test "reg.chula carries the do-not-import caution" do
    visit data_sources_path
    assert_text "Do not import from this source"
  end

  test "chulabooster states it has no course offering data" do
    visit data_sources_path
    assert_text "CB has no such entity"
  end

  test "sources link out to the pages that own the actions" do
    visit data_sources_path
    assert_link "Go to Imports", href: data_imports_path
    assert_link "Run a scrape", href: scrapes_path
  end

  test "the old chulabooster url redirects to data sources" do
    visit "/chulabooster"
    assert_current_path data_sources_path
  end

  test "sidebar shows Data Sources for an admin" do
    visit root_path
    assert_selector "nav a", text: "Data Sources"
  end

  test "a non-admin cannot access data sources" do
    click_on users(:admin).name
    page.execute_script("document.querySelector('button.dropdown-item').click()")
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit data_sources_path
    assert_text "Only admins can perform this action."
  end
end
