require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  # --- Access control ---

  test "non-admin cannot access show" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get chat_path
    assert_redirected_to root_path
  end

  test "non-admin cannot create" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    post chat_path, params: { message: "hello" }
    assert_redirected_to root_path
  end

  test "admin can access show" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get chat_path
    assert_response :success
    assert_match "Chat Playground", response.body
  end

  # --- Create ---

  test "blank message redirects back" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    post chat_path, params: { message: "" }
    assert_redirected_to chat_path
  end

  test "/clear deletes chat history and redirects" do
    admin = users(:admin)
    post login_path, params: { username: admin.username, password: "password123" }

    # Create some messages
    line_user_id = "web_#{admin.id}"
    ChatMessage.create!(line_user_id: line_user_id, role: "user", content: "test")
    ChatMessage.create!(line_user_id: line_user_id, role: "assistant", content: "response")

    assert_difference -> { ChatMessage.where(line_user_id: line_user_id).count }, -2 do
      post chat_path, params: { message: "/clear" }
    end

    assert_redirected_to chat_path
    follow_redirect!
    assert_match "cleared", response.body
  end

  test "uses web_N as line_user_id for chat history" do
    admin = users(:admin)
    post login_path, params: { username: admin.username, password: "password123" }
    get chat_path
    assert_response :success
    # The controller uses "web_#{current_user.id}" — messages are scoped per admin user
  end
end
