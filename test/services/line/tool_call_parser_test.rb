require "test_helper"

class Line::ToolCallParserTest < ActiveSupport::TestCase
  test "parses XML-wrapped JSON tool call" do
    content = '<tool_call>{"name": "student_lookup", "arguments": {"query": "6732100021"}}</tool_call>'
    calls = Line::ToolCallParser.parse(content)

    assert_equal 1, calls.size
    assert_equal "student_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "6732100021" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses GLM arg_key/arg_value format" do
    content = "<tool_call>course_lookup<arg_key>query</arg_key><arg_value>2110327</arg_value></tool_call>"
    calls = Line::ToolCallParser.parse(content)

    assert_equal "course_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "2110327" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses action code block format" do
    content = "```action\nstaff_lookup\n{\"query\": \"สมิธ\"}\n```"
    calls = Line::ToolCallParser.parse(content)

    assert_equal "staff_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "สมิธ" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses bare JSON line" do
    content = '{"name": "search", "arguments": {"query": "NNN"}}'
    calls = Line::ToolCallParser.parse(content)

    assert_equal "search", calls.first.dig("function", "name")
  end

  test "returns nil for plain text" do
    assert_nil Line::ToolCallParser.parse("สวัสดีค่ะ มีอะไรให้ช่วยไหมคะ")
  end
end
