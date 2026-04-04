require "application_system_test_case"

class ChatMessagesTest < ApplicationSystemTestCase
  setup do
    @line_user_id = "U_SYS_TEST_CHAT"

    # Create a conversation with a tool-calling round
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "Test the echo tool")
    ChatMessage.create!(
      line_user_id: @line_user_id, role: "assistant", content: nil,
      tool_calls: [{ "id" => "call_1", "type" => "function", "function" => { "name" => "echo", "arguments" => '{"text":"hello"}' } }]
    )
    ChatMessage.create!(line_user_id: @line_user_id, role: "tool", content: '{"text":"hello"}', tool_call_id: "call_1")
    ChatMessage.create!(line_user_id: @line_user_id, role: "assistant", content: "The echo returned: hello")
  end

  test "admin without debug mode sees clean conversation" do
    admin = users(:admin)
    admin.update!(debug_tool_calls: false)

    visit login_path
    fill_in "Username", with: admin.username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit chat_message_path(@line_user_id)

    # Should see user and final assistant messages
    assert_text "Test the echo tool"
    assert_text "The echo returned: hello"

    # Should NOT see tool chain details
    assert_no_css ".chat-tool-chain"
    assert_no_css ".chat-tool-step"
    assert_no_text "Debug mode"
  end

  test "admin with debug mode sees tool chain inspector" do
    admin = users(:admin)
    admin.update!(debug_tool_calls: true)

    visit login_path
    fill_in "Username", with: admin.username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit chat_message_path(@line_user_id)

    # Should see debug badge
    assert_text "Debug mode"

    # Should see user and final assistant messages
    assert_text "Test the echo tool"
    assert_text "The echo returned: hello"

    # Should see tool chain
    assert_css ".chat-tool-chain"
    assert_css ".chat-tool-step"
    assert_text "echo"  # tool name badge
    assert_text "Arguments"
    assert_text "Result"
  end
end
