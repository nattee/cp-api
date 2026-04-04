require "test_helper"

class ChatMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @line_user_id = "U_CHAT_CTRL_TEST"
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "hello")
    ChatMessage.create!(line_user_id: @line_user_id, role: "assistant", content: "hi there")
  end

  # --- Access control ---

  test "non-admin cannot access index" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get chat_messages_path
    assert_redirected_to root_path
  end

  test "non-admin cannot access show" do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
    get chat_message_path(@line_user_id)
    assert_redirected_to root_path
  end

  test "admin can access index" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get chat_messages_path
    assert_response :success
  end

  test "admin can access show" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get chat_message_path(@line_user_id)
    assert_response :success
  end

  # --- Debug mode ---

  test "show sets debug_mode false by default" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get chat_message_path(@line_user_id)

    assert_response :success
    # Debug badge should not appear
    assert_no_match(/Debug mode/, response.body)
  end

  test "show sets debug_mode true when user has debug_tool_calls enabled" do
    admin = users(:admin)
    admin.update!(debug_tool_calls: true)

    post login_path, params: { username: admin.username, password: "password123" }
    get chat_message_path(@line_user_id)

    assert_response :success
    assert_match(/Debug mode/, response.body)
  end

  test "show redirects when no messages found" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get chat_message_path("U_NONEXISTENT")
    assert_redirected_to chat_messages_path
  end
end
