require "test_helper"

class Line::ToolExecutorTest < ActiveSupport::TestCase
  setup do
    # Ensure echo tool is registered (it should be from initializer,
    # but re-register to be safe in test isolation).
    Line::ToolRegistry.register("echo",
      definition: Line::Tools::EchoTool::DEFINITION,
      handler: Line::Tools::EchoTool)
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
      def self.call(_args)
        raise "something broke"
      end
    end
    Line::ToolRegistry.register("fail_tool",
      definition: { description: "Always fails", parameters: { type: "object", properties: {} } },
      handler: failing_handler)

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
end
