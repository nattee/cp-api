require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "successful login redirects to root" do
    visit login_path

    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    assert_text "Signed in successfully"
    assert_current_path root_path
  end

  test "login with wrong password shows error" do
    visit login_path

    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "wrongpassword"
    click_on "Sign In"

    assert_text "Invalid username or password"
    assert_current_path login_path
  end

  test "inactive user cannot login" do
    visit login_path

    fill_in "Username", with: users(:inactive).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    assert_text "Invalid username or password"
  end

  test "unauthenticated user is redirected to login" do
    visit root_path
    assert_current_path login_path
  end

  test "logout redirects to login page" do
    # Login first
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
    assert_current_path root_path

    # Logout via the sidebar dropdown (opens upward, needs JS click)
    find(".dropdown-toggle", text: users(:admin).name).click
    page.execute_script("document.querySelector('.dropdown-item[type=\"submit\"]').click()")
    assert_text "Signed out successfully"
    assert_current_path login_path
  end
end
