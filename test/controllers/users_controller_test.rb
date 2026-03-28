require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin can view index" do
    get users_path
    assert_response :success
  end

  test "non-admin can view show" do
    get user_path(users(:admin))
    assert_response :success
  end

  test "non-admin cannot access new" do
    get new_user_path
    assert_redirected_to users_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "User.count" do
      post users_path, params: { user: { username: "newuser", email: "new@example.com", name: "New", password: "password123", role: "viewer" } }
    end
    assert_redirected_to users_path
  end

  test "non-admin cannot access edit" do
    get edit_user_path(users(:admin))
    assert_redirected_to users_path
  end

  test "non-admin cannot update" do
    user = users(:admin)
    patch user_path(user), params: { user: { name: "Hacked" } }
    assert_redirected_to users_path
    assert_equal "Admin User", user.reload.name
  end

  test "non-admin cannot delete" do
    assert_no_difference "User.count" do
      delete user_path(users(:admin))
    end
    assert_redirected_to users_path
  end

  # --- LINE code generation (admin-only) ---

  test "non-admin cannot generate line code" do
    user = users(:editor)
    post generate_line_code_user_path(user)
    assert_redirected_to users_path
    assert_equal "Only admins can perform this action.", flash[:alert]
    assert_nil user.reload.line_link_token
  end

  test "non-admin cannot unlink line" do
    user = users(:editor)
    user.update!(provider: "line", uid: "U1234")
    delete unlink_line_user_path(user)
    assert_redirected_to users_path
    assert_equal "line", user.reload.provider
  end

  test "admin can generate line code for a user" do
    delete logout_path
    post login_path, params: { username: users(:admin).username, password: "password123" }

    user = users(:viewer)
    assert_nil user.line_link_token

    freeze_time do
      post generate_line_code_user_path(user)
      assert_redirected_to user_path(user)

      user.reload
      assert_not_nil user.line_link_token
      assert_equal 8, user.line_link_token.length
      assert_equal user.line_link_token, user.line_link_token.upcase
      assert_equal 24.hours.from_now.to_i, user.line_link_token_expires_at.to_i
    end
  end

  test "admin can unlink a user line account" do
    delete logout_path
    post login_path, params: { username: users(:admin).username, password: "password123" }

    user = users(:viewer)
    user.update!(provider: "line", uid: "U1234", llm_consent: true)

    delete unlink_line_user_path(user)
    assert_redirected_to user_path(user)

    user.reload
    assert_nil user.provider
    assert_nil user.uid
    assert_equal false, user.llm_consent
  end

  test "generating a new code replaces the old one" do
    delete logout_path
    post login_path, params: { username: users(:admin).username, password: "password123" }

    user = users(:viewer)
    post generate_line_code_user_path(user)
    old_token = user.reload.line_link_token

    post generate_line_code_user_path(user)
    assert_not_equal old_token, user.reload.line_link_token
  end
end
