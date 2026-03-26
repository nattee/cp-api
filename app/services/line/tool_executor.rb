# Dispatches tool_calls from an LLM response to registered handlers.
# Returns an array of tool-result messages ready to append to the conversation.
#
# Each tool_call is a hash like:
#   { "id" => "call_123", "function" => { "name" => "echo", "arguments" => "{\"text\":\"hi\"}" } }
#
# If a handler raises, the error message is returned as the tool result
# so the LLM can recover gracefully.
class Line::ToolExecutor
  def self.execute(tool_calls)
    tool_calls.map do |tool_call|
      name = tool_call.dig("function", "name")
      raw_args = tool_call.dig("function", "arguments")
      call_id = tool_call["id"]

      result = invoke(name, raw_args)

      { role: "tool", tool_call_id: call_id, content: result.to_s }
    end
  end

  def self.invoke(name, raw_args)
    handler = Line::ToolRegistry.handler_for(name)
    unless handler
      return "Error: unknown tool '#{name}'"
    end

    arguments = raw_args.is_a?(String) ? JSON.parse(raw_args) : raw_args
    handler.call(arguments)
  rescue JSON::ParserError => e
    "Error: invalid arguments JSON — #{e.message}"
  rescue => e
    Rails.logger.error("Tool '#{name}' failed: #{e.message}")
    "Error: #{e.message}"
  end
  private_class_method :invoke
end
