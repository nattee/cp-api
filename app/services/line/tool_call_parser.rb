# Parses tool calls that models embed in message CONTENT instead of the
# structured tool_calls array: <tool_call>/<tools> XML tags (JSON or GLM's
# <arg_key>/<arg_value> pairs inside), ```action``` code blocks, and bare
# JSON lines with "name" + "arguments" keys. Returns an array of tool_call
# hashes in OpenAI format, or nil when the content contains none.
#
# Extracted from LlmService so the llm:eval harness (lib/tasks/llm_eval.rake)
# scores content-embedded tool calls exactly the way production does.
module Line::ToolCallParser
  TOOL_CALL_PATTERN = /<tool_call>\s*(.*?)\s*<\/tool_call>|<tools>\s*(.*?)\s*<\/tools>/m
  ACTION_BLOCK_PATTERN = /```action\s*\n(\S+)\s*\n(.*?)```/m
  ARG_KV_PATTERN = /<arg_key>\s*(.*?)\s*<\/arg_key>\s*<arg_value>\s*(.*?)\s*<\/arg_value>/m

  module_function

  def parse(content)
    matches = content.scan(TOOL_CALL_PATTERN)
    return build_calls_from_matches(matches) if matches.present?

    action = parse_action_block(content)
    return action if action.present?

    try_parse_bare_tool_call(content).presence
  end

  def build_calls_from_matches(matches)
    calls = matches.flat_map do |tool_call_match, tools_match|
      raw = (tool_call_match || tools_match).strip

      if raw.match?(ARG_KV_PATTERN)
        parse_arg_kv_tool_call(raw)
      else
        raw.split("\n").filter_map { |line| parse_single_tool_json(line) }
      end
    end
    calls.presence
  end

  def parse_arg_kv_tool_call(raw)
    name = raw.sub(/<arg_key>.*\z/m, "").strip
    return [] if name.empty?

    args = {}
    raw.scan(ARG_KV_PATTERN).each { |k, v| args[k.strip] = v.strip }

    [{
      "id" => "fallback_#{SecureRandom.hex(4)}",
      "type" => "function",
      "function" => { "name" => name, "arguments" => args.to_json }
    }]
  end

  def parse_action_block(content)
    matches = content.scan(ACTION_BLOCK_PATTERN)
    return nil if matches.empty?

    calls = matches.filter_map do |name, body|
      args = JSON.parse(body.strip)
      {
        "id" => "fallback_#{SecureRandom.hex(4)}",
        "type" => "function",
        "function" => { "name" => name.strip, "arguments" => args.to_json }
      }
    rescue JSON::ParserError
      nil
    end
    calls.presence
  end

  def try_parse_bare_tool_call(content)
    calls = content.strip.split("\n").filter_map { |line| parse_single_tool_json(line) }
    calls.presence
  end

  def parse_single_tool_json(line)
    line = line.strip
    return nil if line.empty?
    parsed = JSON.parse(line)
    return nil unless parsed.is_a?(Hash) && parsed["name"].present? && parsed.key?("arguments")
    {
      "id" => "fallback_#{SecureRandom.hex(4)}",
      "type" => "function",
      "function" => {
        "name" => parsed["name"],
        "arguments" => parsed["arguments"].is_a?(String) ? parsed["arguments"] : parsed["arguments"].to_json
      }
    }
  rescue JSON::ParserError
    nil
  end
end
