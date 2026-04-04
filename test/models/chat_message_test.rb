require "test_helper"

class ChatMessageTest < ActiveSupport::TestCase
  setup do
    @line_user_id = "U_TEST_CHAT_123"
  end

  # --- Validations ---

  test "valid message is valid" do
    msg = ChatMessage.new(line_user_id: @line_user_id, role: "user", content: "hello")
    assert msg.valid?
  end

  test "requires line_user_id" do
    msg = ChatMessage.new(role: "user", content: "hello")
    assert_not msg.valid?
    assert_includes msg.errors[:line_user_id], "can't be blank"
  end

  test "requires role" do
    msg = ChatMessage.new(line_user_id: @line_user_id, content: "hello")
    assert_not msg.valid?
    assert_includes msg.errors[:role], "can't be blank"
  end

  test "rejects invalid role" do
    msg = ChatMessage.new(line_user_id: @line_user_id, role: "system", content: "hello")
    assert_not msg.valid?
    assert_includes msg.errors[:role], "is not included in the list"
  end

  test "accepts valid roles" do
    %w[user assistant tool].each do |role|
      msg = ChatMessage.new(line_user_id: @line_user_id, role: role, content: "hello")
      assert msg.valid?, "#{role} should be a valid role"
    end
  end

  # --- to_llm_message ---

  test "to_llm_message returns basic message hash" do
    msg = ChatMessage.new(role: "user", content: "hello")
    result = msg.to_llm_message
    assert_equal({ "role" => "user", "content" => "hello" }, result)
  end

  test "to_llm_message includes tool_calls when present" do
    tool_calls = [{ "id" => "call_1", "function" => { "name" => "echo", "arguments" => '{"text":"hi"}' } }]
    msg = ChatMessage.new(role: "assistant", content: nil, tool_calls: tool_calls)
    result = msg.to_llm_message
    assert_equal tool_calls, result["tool_calls"]
  end

  test "to_llm_message excludes tool_calls when blank" do
    msg = ChatMessage.new(role: "assistant", content: "hi")
    result = msg.to_llm_message
    assert_not result.key?("tool_calls")
  end

  test "to_llm_message includes tool_call_id when present" do
    msg = ChatMessage.new(role: "tool", content: '{"text":"hi"}', tool_call_id: "call_1")
    result = msg.to_llm_message
    assert_equal "call_1", result["tool_call_id"]
  end

  test "to_llm_message excludes tool_call_id when blank" do
    msg = ChatMessage.new(role: "user", content: "hi")
    result = msg.to_llm_message
    assert_not result.key?("tool_call_id")
  end

  # --- recent_for scope ---

  test "recent_for returns messages for the given user only" do
    other_user_id = "U_OTHER"
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "mine")
    ChatMessage.create!(line_user_id: other_user_id, role: "user", content: "theirs")

    results = ChatMessage.recent_for(@line_user_id)
    assert_equal 1, results.size
    assert_equal "mine", results.first.content
  end

  test "recent_for excludes messages older than expiry window" do
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "old", created_at: 25.hours.ago)
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "recent")

    results = ChatMessage.recent_for(@line_user_id)
    assert_equal 1, results.size
    assert_equal "recent", results.first.content
  end

  test "recent_for respects HISTORY_LIMIT" do
    (ChatMessage::HISTORY_LIMIT + 5).times do |i|
      ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "msg #{i}")
    end

    results = ChatMessage.recent_for(@line_user_id)
    assert_equal ChatMessage::HISTORY_LIMIT, results.size
  end

  test "recent_for returns messages in ascending order" do
    ChatMessage.create!(line_user_id: @line_user_id, role: "user", content: "first", created_at: 2.minutes.ago)
    ChatMessage.create!(line_user_id: @line_user_id, role: "assistant", content: "second", created_at: 1.minute.ago)

    results = ChatMessage.recent_for(@line_user_id)
    assert_equal %w[first second], results.map(&:content)
  end
end
