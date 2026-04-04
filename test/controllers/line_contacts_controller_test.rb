require "test_helper"

class LineContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @contact = LineContact.create!(
      line_user_id: "U_CTRL_TEST",
      display_name: "Test VIP",
      recent_messages: [{ "text" => "Hello", "at" => Time.current.iso8601 }],
      message_count: 1,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end

  # --- Access control ---

  test "non-admin cannot access index" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get line_contacts_path
    assert_redirected_to root_path
  end

  test "non-admin cannot access show" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get line_contact_path(@contact)
    assert_redirected_to root_path
  end

  test "non-admin cannot access new_user" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get new_user_line_contact_path(@contact)
    assert_redirected_to root_path
  end

  # --- Admin access ---

  test "admin can access index" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get line_contacts_path
    assert_response :success
    assert_match "Test VIP", response.body
  end

  test "admin can access show" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get line_contact_path(@contact)
    assert_response :success
    assert_match "U_CTRL_TEST", response.body
    assert_match "Hello", response.body
  end

  test "admin can access new_user form" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get new_user_line_contact_path(@contact)
    assert_response :success
    assert_match "Create &amp; Link", response.body
  end

  # --- Create & Link ---

  test "create_user creates user and deletes contact" do
    post login_path, params: { username: users(:admin).username, password: "password123" }

    assert_difference "User.count", 1 do
      assert_difference "LineContact.count", -1 do
        post create_user_line_contact_path(@contact), params: {
          user: {
            username: "vip_user",
            email: "vip@example.com",
            name: "VIP Person",
            password: "password123",
            password_confirmation: "password123",
            role: "viewer"
          }
        }
      end
    end

    assert_redirected_to chat_messages_path

    user = User.find_by(username: "vip_user")
    assert_equal "line", user.provider
    assert_equal "U_CTRL_TEST", user.uid
    assert user.llm_consent?
    assert_equal "viewer", user.role
  end

  test "create_user re-renders form on validation error" do
    post login_path, params: { username: users(:admin).username, password: "password123" }

    assert_no_difference "User.count" do
      post create_user_line_contact_path(@contact), params: {
        user: { username: "", email: "", name: "", password: "", role: "viewer" }
      }
    end

    assert_response :unprocessable_entity
  end
end
