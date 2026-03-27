# Sends a user message to a vLLM instance (OpenAI-compatible API) and returns
# the assistant's text reply. Runs a tool-calling loop: when vLLM returns
# tool_calls, ToolExecutor dispatches them and feeds results back. The loop
# ends when vLLM returns plain text or max_rounds is reached.
#
# Conversation history is stored in chat_messages and loaded per LINE user.
# Only the last 20 messages within 24 hours are included.
class Line::LlmService
  class LlmError < StandardError; end

  def initialize(user_message, line_user_id:, user: nil)
    @user_message = user_message
    @line_user_id = line_user_id
    @user = user
    @max_rounds = LLM_CONFIG[:max_rounds] || 5
    @model_config = resolve_model_config
  end

  # Returns the assistant's final text reply as a plain String.
  def call
    # Save the incoming user message to history.
    save_message(role: "user", content: @user_message)

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
          assistant_message = { "role" => "assistant", "tool_calls" => tool_calls }
        end
      end

      # No tool calls — the LLM produced a final text answer.
      if tool_calls.blank?
        reply = assistant_message["content"].to_s.strip
        save_message(role: "assistant", content: reply)
        return reply
      end

      # Append the assistant's tool-call message to the conversation.
      messages << assistant_message

      # Execute each tool and append results to the conversation.
      tool_results = Line::ToolExecutor.execute(tool_calls)
      messages.concat(tool_results)

      # Tool-calling rounds are not saved to history — they're transient
      # within a single request. Only the final user/assistant pair persists.

      Rails.logger.info("LLM tool-calling round #{round + 1}: #{tool_calls.map { |tc| tc.dig("function", "name") }.join(", ")}")
    end

    # Safety net: max rounds exhausted, extract whatever content we have.
    Rails.logger.warn("LLM reached max rounds (#{@max_rounds}) without final text reply")
    fallback = messages.last&.dig("content").to_s.strip.presence || "I'm sorry, I couldn't complete that request."
    save_message(role: "assistant", content: fallback)
    fallback
  end

  private

  # Assembles the message array: system prompt + recent history + current user message.
  def build_initial_messages
    messages = []
    messages << { "role" => "system", "content" => system_prompt } if system_prompt.present?

    # Load conversation history (already includes the message we just saved).
    history = ChatMessage.recent_for(@line_user_id)
    history.each { |msg| messages << msg.to_llm_message }

    messages
  end

  def system_prompt
    LLM_CONFIG[:system_prompt]
  end

  # Picks the model config hash from LLM_CONFIG[:models] based on the user's
  # preference, falling back to the default model if unset or invalid.
  def resolve_model_config
    key = @user&.llm_model.presence || LLM_CONFIG[:default_model].to_s
    LLM_CONFIG[:models][key.to_sym] || LLM_CONFIG[:models][LLM_CONFIG[:default_model].to_sym]
  end

  def save_message(role:, content:, tool_calls: nil, tool_call_id: nil)
    ChatMessage.create!(
      line_user_id: @line_user_id,
      role: role,
      content: content,
      tool_calls: tool_calls,
      tool_call_id: tool_call_id
    )
  end

  # POSTs to the OpenAI-compatible /v1/chat/completions endpoint.
  # Includes tool definitions when available.
  # Raises LlmError on non-2xx responses.
  def chat_completion(messages, tools: [])
    uri = URI("#{@model_config[:base_url]}#{@model_config[:endpoint]}")
    body = {
      model: @model_config[:model],
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
