require "test_helper"

# Local stand-in for the retired echo tool: returns its arguments as JSON,
# which is exactly what the executor tests assert on.
class LlmServiceStubEcho
  def self.call(arguments, user: nil)
    arguments.to_json
  end
end

class Line::LlmServiceTest < ActiveSupport::TestCase
  setup do
    @line_user_id = "U_LLM_TEST_123"
    @user = users(:viewer)

    Line::ToolRegistry.register("echo",
      definition: { description: "test echo", parameters: { type: "object", properties: { text: { type: "string" } } } },
      handler: LlmServiceStubEcho,
      permission: "courses.read")

    ChatMessage.where(line_user_id: @line_user_id).delete_all
  end

  test "persists user message and final assistant reply" do
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: @user)
    responses = [text_response("Hello!")]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_equal "Hello!", result.reply
    end

    messages = ChatMessage.where(line_user_id: @line_user_id).order(:created_at)
    assert_equal 2, messages.size
    assert_equal "user", messages.first.role
    assert_equal "Hi", messages.first.content
    assert_equal "assistant", messages.second.role
    assert_equal "Hello!", messages.second.content
  end

  test "persists intermediate tool-call and tool-result messages" do
    service = Line::LlmService.new("Test tools", line_user_id: @line_user_id, user: @user)
    responses = [
      tool_call_response("echo", '{"text":"ping"}', call_id: "call_1"),
      text_response("The echo said: ping")
    ]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_equal "The echo said: ping", result.reply
    end

    messages = ChatMessage.where(line_user_id: @line_user_id).order(:created_at)
    # user -> assistant(tool_calls) -> tool(result) -> assistant(final)
    assert_equal 4, messages.size

    assert_equal "user", messages[0].role
    assert_equal "Test tools", messages[0].content

    assert_equal "assistant", messages[1].role
    assert messages[1].tool_calls.present?, "Intermediate assistant should have tool_calls"
    assert_equal "echo", messages[1].tool_calls.first.dig("function", "name")

    assert_equal "tool", messages[2].role
    assert_equal "call_1", messages[2].tool_call_id
    assert_equal '{"text":"ping"}', messages[2].content

    assert_equal "assistant", messages[3].role
    assert_equal "The echo said: ping", messages[3].content
  end

  test "persists multiple rounds of tool calls" do
    service = Line::LlmService.new("Multi-round", line_user_id: @line_user_id, user: @user)
    responses = [
      tool_call_response("echo", '{"text":"first"}', call_id: "call_1"),
      tool_call_response("echo", '{"text":"second"}', call_id: "call_2"),
      text_response("Done with two rounds")
    ]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_equal "Done with two rounds", result.reply
    end

    messages = ChatMessage.where(line_user_id: @line_user_id).order(:created_at)
    # user -> assistant(tc1) -> tool(r1) -> assistant(tc2) -> tool(r2) -> assistant(final)
    assert_equal 6, messages.size
    assert_equal %w[user assistant tool assistant tool assistant], messages.map(&:role)
  end

  # --- Result struct ---

  test "call returns Result with reply and empty tool_rounds when no tools used" do
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: @user)
    responses = [text_response("Hello!")]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_instance_of Line::LlmService::Result, result
      assert_equal "Hello!", result.reply
      assert_equal [], result.tool_rounds
    end
  end

  test "call returns Result with populated tool_rounds when tools used" do
    service = Line::LlmService.new("Test", line_user_id: @line_user_id, user: @user)
    responses = [
      tool_call_response("echo", '{"text":"ping"}', call_id: "call_1"),
      text_response("Done")
    ]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_equal "Done", result.reply
      assert_equal 1, result.tool_rounds.size

      round = result.tool_rounds.first
      assert_equal 1, round[:round]
      assert_equal "echo", round[:tool]
      assert_equal '{"text":"ping"}', round[:arguments]
      assert_equal '{"text":"ping"}', round[:result]
    end
  end

  # --- Graceful degradation when a swapped-out resident is offline ---

  test "falls back to the default model when the selected resident is unreachable" do
    viewer = users(:viewer)
    viewer.llm_model = "glm" # a swap resident, usually offline
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: viewer)

    # First call (the chosen glm on :8001) refuses; the retry against the default
    # (qwen) answers.
    calls = 0
    service.define_singleton_method(:chat_completion) do |_messages, tools: []|
      calls += 1
      raise Line::LlmService::LlmConnectionError, "connection refused" if calls == 1

      { "choices" => [{ "message" => { "role" => "assistant", "content" => "Hello from the default" } }] }
    end

    result = service.call
    assert_equal 2, calls, "should retry exactly once against the default model"
    assert_includes result.reply, "Hello from the default"
    assert_match(/ไม่พร้อมใช้งาน/, result.reply, "should prepend an offline notice naming the situation")

    # The saved assistant message is the real answer, without the transient notice.
    last = ChatMessage.where(line_user_id: @line_user_id, role: "assistant").order(:created_at).last
    assert_equal "Hello from the default", last.content
  end

  # --- Markdown scrubbing at the source (before save, not just delivery) ---

  test "final reply is scrubbed of Markdown before returning and before saving" do
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: @user)
    # Header on its own line so the ATX rule (line-start only, by design) applies;
    # a mid-sentence "##" is left alone as ambiguous (see scrubber file header).
    responses = [text_response("**สรุป**: ได้\n## ดีมาก")]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_includes result.reply, "สรุป"
      assert_not_includes result.reply, "**"
      assert_not_includes result.reply, "##"
    end

    last = ChatMessage.where(line_user_id: @line_user_id, role: "assistant").order(:created_at).last
    assert_includes last.content, "สรุป"
    assert_not_includes last.content, "**"
    assert_not_includes last.content, "##"
  end

  test "a connection error on the default model surfaces (nothing to fall back to)" do
    viewer = users(:viewer)
    viewer.llm_model = nil # default resident (qwen)
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: viewer)

    service.define_singleton_method(:chat_completion) do |_messages, tools: []|
      raise Line::LlmService::LlmConnectionError, "connection refused"
    end

    assert_raises(Line::LlmService::LlmConnectionError) { service.call }
  end

  private

  def text_response(content)
    {
      "choices" => [{
        "message" => { "role" => "assistant", "content" => content }
      }]
    }
  end

  def tool_call_response(name, arguments, call_id: "call_1")
    {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [{
            "id" => call_id,
            "type" => "function",
            "function" => { "name" => name, "arguments" => arguments }
          }]
        }
      }]
    }
  end

  # Stubs the private chat_completion method to return canned responses in sequence.
  def stub_chat_completion(service, responses)
    call_index = 0
    service.define_singleton_method(:chat_completion) do |_messages, tools: []|
      resp = responses[call_index]
      call_index += 1
      resp
    end
    yield
  end
end
