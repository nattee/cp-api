require "test_helper"

# Local stand-in for the retired echo tool: returns its arguments as JSON,
# which is exactly what the executor tests assert on.
class ToolExecutorStubEcho
  def self.call(arguments, user: nil)
    arguments.to_json
  end
end

class Line::ToolExecutorTest < ActiveSupport::TestCase
  setup do
    Line::ToolRegistry.register("echo",
      definition: { description: "test echo", parameters: { type: "object", properties: { text: { type: "string" } } } },
      handler: ToolExecutorStubEcho,
      permission: "courses.read")
  end

  test "execute returns tool result messages" do
    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "echo", "arguments" => '{"text":"hi"}' } }
    ]

    results = Line::ToolExecutor.execute(tool_calls)

    assert_equal 1, results.size
    assert_equal "tool", results.first[:role]
    assert_equal "call_1", results.first[:tool_call_id]
    assert_equal '{"text":"hi"}', results.first[:content]
  end

  test "execute logs ApiEvent on successful tool call" do
    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "echo", "arguments" => '{"text":"hi"}' } }
    ]

    assert_difference -> { ApiEvent.where(action: "tool_call", severity: "info").count }, 1 do
      Line::ToolExecutor.execute(tool_calls)
    end

    event = ApiEvent.where(action: "tool_call").last
    assert_equal "llm", event.service
    assert_equal "info", event.severity
    assert_equal "Tool: echo", event.message
    assert_equal "echo", event.details["tool"]
    assert_equal({ "text" => "hi" }, event.details["arguments"])
  end

  test "execute logs warning for unknown tool" do
    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "nonexistent", "arguments" => "{}" } }
    ]

    assert_difference -> { ApiEvent.where(action: "tool_call", severity: "warning").count }, 1 do
      results = Line::ToolExecutor.execute(tool_calls)
      assert_match(/unknown tool/, results.first[:content])
    end

    event = ApiEvent.where(action: "tool_call", severity: "warning").last
    assert_equal "Unknown tool: nonexistent", event.message
  end

  test "execute logs error on invalid JSON arguments" do
    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "echo", "arguments" => "not json" } }
    ]

    assert_difference -> { ApiEvent.where(action: "tool_call", severity: "error").count }, 1 do
      results = Line::ToolExecutor.execute(tool_calls)
      assert_match(/invalid arguments JSON/, results.first[:content])
    end

    event = ApiEvent.where(action: "tool_call", severity: "error").last
    assert_match(/parse error/, event.message)
  end

  test "execute logs error when handler raises" do
    # Register a tool that always raises
    failing_handler = Class.new do
      def self.call(_args, user: nil)
        raise "something broke"
      end
    end
    Line::ToolRegistry.register("fail_tool",
      definition: { description: "Always fails", parameters: { type: "object", properties: {} } },
      handler: failing_handler,
      permission: "courses.read")

    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "fail_tool", "arguments" => "{}" } }
    ]

    assert_difference -> { ApiEvent.where(action: "tool_call", severity: "error").count }, 1 do
      results = Line::ToolExecutor.execute(tool_calls)
      assert_match(/something broke/, results.first[:content])
    end

    event = ApiEvent.where(action: "tool_call", severity: "error").last
    assert_equal "Tool failed: fail_tool", event.message
    assert_equal "something broke", event.details["error"]
  end

  test "execute handles multiple tool calls" do
    tool_calls = [
      { "id" => "call_1", "function" => { "name" => "echo", "arguments" => '{"text":"a"}' } },
      { "id" => "call_2", "function" => { "name" => "echo", "arguments" => '{"text":"b"}' } }
    ]

    assert_difference -> { ApiEvent.where(action: "tool_call").count }, 2 do
      results = Line::ToolExecutor.execute(tool_calls)
      assert_equal 2, results.size
    end
  end

  test "execute passes user to handlers" do
    probe = Class.new do
      class << self
        attr_accessor :received_user

        def call(_arguments, user: nil)
          self.received_user = user
          "ok"
        end
      end
    end
    Line::ToolRegistry.register("probe_tool",
      definition: { description: "probe", parameters: { type: "object", properties: {} } },
      handler: probe,
      permission: "courses.read")

    # A fixture user (not User.new) because gate 2 now checks user.can? — an
    # unsaved User.new has no role, so it would be denied before reaching the
    # handler, defeating the point of this pass-through test.
    user = users(:viewer)
    Line::ToolExecutor.execute(
      [ { "id" => "call_1", "function" => { "name" => "probe_tool", "arguments" => "{}" } } ],
      user: user
    )

    assert_same user, probe.received_user
  end
end
