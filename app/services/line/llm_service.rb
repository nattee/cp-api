# Sends a user message to a vLLM instance (OpenAI-compatible API) and returns
# the assistant's text reply. Runs a tool-calling loop: when vLLM returns
# tool_calls, ToolExecutor dispatches them and feeds results back. The loop
# ends when vLLM returns plain text or max_rounds is reached.
#
# Conversation history is stored in chat_messages and loaded per LINE user.
# Only the last 40 messages within 24 hours are included.
#
# Returns a Result with .reply (String) and .tool_rounds (Array of hashes).
# Callers that only need the text can use .reply directly.
class Line::LlmService
  class LlmError < StandardError; end
  Result = Struct.new(:reply, :tool_rounds, keyword_init: true)

  def initialize(user_message, line_user_id:, user: nil)
    @user_message = user_message
    @line_user_id = line_user_id
    @user = user
    @max_rounds = LLM_CONFIG[:max_rounds] || 5
    @model_config = resolve_model_config
    @tool_rounds = []
  end

  # Returns a Result with .reply and .tool_rounds.
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
        return Result.new(reply: reply, tool_rounds: @tool_rounds)
      end

      # Append the assistant's tool-call message to the conversation.
      messages << assistant_message

      # Execute each tool and append results to the conversation.
      tool_results = Line::ToolExecutor.execute(tool_calls)
      messages.concat(tool_results)

      # Persist intermediate messages for audit trail.
      save_message(role: "assistant", content: assistant_message["content"], tool_calls: tool_calls)
      tool_results.each do |tr|
        save_message(role: "tool", content: tr[:content], tool_call_id: tr[:tool_call_id])
      end

      # Record the round for in-memory debugging (chat playground, rake task).
      tool_calls.zip(tool_results).each do |tc, tr|
        @tool_rounds << {
          round: round + 1,
          tool: tc.dig("function", "name"),
          arguments: tc.dig("function", "arguments"),
          result: tr[:content]
        }
      end

      Rails.logger.info("LLM tool-calling round #{round + 1}: #{tool_calls.map { |tc| tc.dig("function", "name") }.join(", ")}")
    end

    # Safety net: max rounds exhausted, extract whatever content we have.
    Rails.logger.warn("LLM reached max rounds (#{@max_rounds}) without final text reply")
    fallback = messages.last&.dig("content").to_s.strip.presence || "I'm sorry, I couldn't complete that request."
    save_message(role: "assistant", content: fallback)
    Result.new(reply: fallback, tool_rounds: @tool_rounds)
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

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 30) do |http|
      http.post(uri, body.to_json, "Content-Type" => "application/json")
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

    unless response.is_a?(Net::HTTPSuccess)
      msg = "vLLM returned #{response.code}: #{response.body}"
      ApiEvent.log(service: "llm", action: "chat_completion", message: msg, details: { endpoint: uri.to_s, status: response.code }, response_time_ms: elapsed_ms)
      raise LlmError, msg
    end

    parsed = JSON.parse(response.body)
    assistant_msg = parsed.dig("choices", 0, "message")
    tool_names = tools.map { |t| t.dig(:function, :name) }
    has_tool_calls = assistant_msg&.key?("tool_calls") && assistant_msg["tool_calls"].present?

    ApiEvent.log(service: "llm", action: "chat_completion", severity: "info", message: "OK",
                 details: {
                   endpoint: uri.to_s,
                   model: @model_config[:model],
                   tools_sent: tool_names,
                   tool_calls_returned: has_tool_calls,
                   response_preview: assistant_msg&.slice("role", "content", "tool_calls").to_s.truncate(1000)
                 }, response_time_ms: elapsed_ms)

    parsed
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    msg = "vLLM connection failed: #{e.class} — #{e.message}"
    Rails.logger.error("[vLLM] #{msg}")
    ApiEvent.log(service: "llm", action: "chat_completion", message: msg, details: { endpoint: uri.to_s, exception: e.class.name })
    raise LlmError, msg
  rescue JSON::ParserError => e
    msg = "vLLM returned invalid JSON: #{e.message}"
    Rails.logger.error("[vLLM] #{msg}")
    ApiEvent.log(service: "llm", action: "chat_completion", message: msg, details: { endpoint: uri.to_s, body: response&.body&.truncate(500) })
    raise LlmError, msg
  end

  # Fallback parser for tool calls embedded in content as XML tags or bare JSON.
  # Handles: <tool_call>...</tool_call>, <tools>...</tools>, and bare JSON with
  # "name" + "arguments" keys (some models skip the XML wrapper entirely).
  # Returns an array of tool_call hashes matching the OpenAI format, or nil.
  TOOL_CALL_PATTERN = /<tool_call>\s*(.*?)\s*<\/tool_call>|<tools>\s*(.*?)\s*<\/tools>/m

  def parse_tool_calls_from_content(content)
    # Try XML-wrapped format first.
    matches = content.scan(TOOL_CALL_PATTERN)
    if matches.present?
      return build_calls_from_matches(matches)
    end

    # Try bare JSON: the entire content (or a line) is a JSON object with "name" + "arguments".
    bare = try_parse_bare_tool_call(content)
    bare.presence
  end

  def build_calls_from_matches(matches)
    calls = matches.flat_map do |tool_call_match, tools_match|
      raw = (tool_call_match || tools_match).strip
      raw.split("\n").filter_map { |line| parse_single_tool_json(line) }
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
