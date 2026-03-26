# Sends a user message to a vLLM instance (OpenAI-compatible API) and returns
# the assistant's text reply. Runs a tool-calling loop: when vLLM returns
# tool_calls, ToolExecutor dispatches them and feeds results back. The loop
# ends when vLLM returns plain text or max_rounds is reached.
class Line::LlmService
  class LlmError < StandardError; end

  def initialize(user_message, user: nil)
    @user_message = user_message
    @user = user # reserved for future per-user context
    @config = LLM_CONFIG
    @max_rounds = @config[:max_rounds] || 5
  end

  # Returns the assistant's final text reply as a plain String.
  def call
    messages = build_initial_messages
    tools = Line::ToolRegistry.definitions

    @max_rounds.times do |round|
      response = chat_completion(messages, tools: tools)
      assistant_message = response.dig("choices", 0, "message")

      tool_calls = assistant_message["tool_calls"]

      # Fallback: some models (e.g. qwen2.5-coder) output tool calls as
      # <tools> or <tool_call> tags in content instead of the structured
      # tool_calls array. Parse them client-side when vLLM's parser misses.
      if tool_calls.blank?
        parsed = parse_tool_calls_from_content(assistant_message["content"].to_s)
        if parsed.present?
          tool_calls = parsed
          # Rewrite assistant_message so the conversation history is well-formed.
          assistant_message = { "role" => "assistant", "tool_calls" => tool_calls }
        end
      end

      # No tool calls — the LLM produced a final text answer.
      if tool_calls.blank?
        return assistant_message["content"].to_s.strip
      end

      # Append the assistant's tool-call message to the conversation.
      messages << assistant_message

      # Execute each tool and append results to the conversation.
      tool_results = Line::ToolExecutor.execute(tool_calls)
      messages.concat(tool_results)

      Rails.logger.info("LLM tool-calling round #{round + 1}: #{tool_calls.map { |tc| tc.dig("function", "name") }.join(", ")}")
    end

    # Safety net: max rounds exhausted, extract whatever content we have.
    Rails.logger.warn("LLM reached max rounds (#{@max_rounds}) without final text reply")
    messages.last&.dig("content").to_s.strip.presence || "I'm sorry, I couldn't complete that request."
  end

  private

  # Assembles the initial message array sent to the LLM.
  def build_initial_messages
    messages = []
    messages << { role: "system", content: system_prompt } if system_prompt.present?
    messages << { role: "user", content: @user_message }
    messages
  end

  def system_prompt
    @config[:system_prompt]
  end

  # POSTs to the OpenAI-compatible /v1/chat/completions endpoint.
  # Includes tool definitions when available.
  # Raises LlmError on non-2xx responses.
  def chat_completion(messages, tools: [])
    uri = URI("#{@config[:base_url]}#{@config[:endpoint]}")
    body = {
      model: @config[:model],
      messages: messages,
      temperature: 0.7
    }
    body[:tools] = tools if tools.present?

    response = Net::HTTP.post(
      uri,
      body.to_json,
      "Content-Type" => "application/json"
    )

    unless response.is_a?(Net::HTTPSuccess)
      raise LlmError, "vLLM returned #{response.code}: #{response.body}"
    end

    JSON.parse(response.body)
  end

  # Fallback parser for tool calls embedded in content as XML tags.
  # Handles both <tool_call>...</tool_call> and <tools>...</tools> formats.
  # Returns an array of tool_call hashes matching the OpenAI format, or nil.
  TOOL_CALL_PATTERN = /<tool_call>\s*(.*?)\s*<\/tool_call>|<tools>\s*(.*?)\s*<\/tools>/m

  def parse_tool_calls_from_content(content)
    matches = content.scan(TOOL_CALL_PATTERN)
    return nil if matches.empty?

    calls = matches.flat_map do |tool_call_match, tools_match|
      raw = (tool_call_match || tools_match).strip
      # Content may have multiple JSON objects (one per line)
      raw.split("\n").filter_map do |line|
        line = line.strip
        next if line.empty?
        parsed = JSON.parse(line)
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

    calls.presence
  end
end
