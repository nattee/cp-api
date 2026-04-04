require "test_helper"

class Line::LlmServiceTest < ActiveSupport::TestCase
  setup do
    @line_user_id = "U_LLM_TEST_123"
    @user = users(:viewer)

    Line::ToolRegistry.register("echo",
      definition: Line::Tools::EchoTool::DEFINITION,
      handler: Line::Tools::EchoTool)

    ChatMessage.where(line_user_id: @line_user_id).delete_all
  end

  test "persists user message and final assistant reply" do
    service = Line::LlmService.new("Hi", line_user_id: @line_user_id, user: @user)
    responses = [text_response("Hello!")]
    stub_chat_completion(service, responses) do
      result = service.call
      assert_equal "Hello!", result
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
      assert_equal "The echo said: ping", result
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
      assert_equal "Done with two rounds", result
    end

    messages = ChatMessage.where(line_user_id: @line_user_id).order(:created_at)
    # user -> assistant(tc1) -> tool(r1) -> assistant(tc2) -> tool(r2) -> assistant(final)
    assert_equal 6, messages.size
    assert_equal %w[user assistant tool assistant tool assistant], messages.map(&:role)
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
