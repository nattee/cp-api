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
        reply = "ขออภัยค่ะ ระบบไม่สามารถสร้างคำตอบได้ กรุณาลองใหม่อีกครั้ง" if reply.empty?
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
  # Sanitizes the sequence so the LLM always receives a valid conversation:
  #  - Removes incomplete tool-call rounds (assistant tool_call + tool results
  #    not followed by an assistant text reply). These occur when a previous
  #    request timed out after tools executed but before the LLM answered.
  #  - Collapses consecutive user messages into just the last one (duplicates
  #    arise when the user retries after a failed request).
  def build_initial_messages
    messages = []
    messages << { "role" => "system", "content" => system_prompt } if system_prompt.present?

    raw = ChatMessage.recent_for(@line_user_id).map(&:to_llm_message)

    # Remove incomplete tool-call rounds anywhere in the history.
    # A valid tool-call round is: assistant(tool_calls) → tool(s) → assistant(text).
    # If the closing assistant text is missing, drop the entire round.
    sanitized = []
    i = 0
    while i < raw.size
      msg = raw[i]
      if msg["role"] == "assistant" && msg["tool_calls"].present?
        # Scan ahead: collect tool results, then look for a closing assistant text.
        round_msgs = [msg]
        j = i + 1
        j += 1 while j < raw.size && raw[j]["role"] == "tool" && round_msgs << raw[j]
        if j < raw.size && raw[j]["role"] == "assistant" && raw[j]["tool_calls"].blank?
          # Complete round — keep all messages including the closing assistant.
          sanitized.concat(round_msgs)
          sanitized << raw[j]
          i = j + 1
        else
          # Incomplete round — skip the assistant(tool_calls) + tool messages.
          i = j
        end
      else
        sanitized << msg
        i += 1
      end
    end

    # Drop assistant messages that are raw unparsed tool calls — artifacts of
    # earlier failed rounds where the fallback parser wasn't yet deployed.
    sanitized.reject! do |msg|
      msg["role"] == "assistant" && msg["tool_calls"].blank? &&
        msg["content"].to_s.match?(/\A\s*<tool_call>|```action\s*\n/m)
    end

    # Collapse consecutive user messages — keep only the last in each run.
    deduped = []
    sanitized.each do |msg|
      if msg["role"] == "user" && deduped.last && deduped.last["role"] == "user"
        deduped[-1] = msg
      else
        deduped << msg
      end
    end

    messages.concat(deduped)
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
  #
  # Logging is controlled by LLM_CONFIG[:log_level]:
  #   "full"    — stores complete request body + complete response body in
  #               api_events.details. Enables exact replay of any call.
  #   "headers" — stores metadata only: message count, payload bytes, tool
  #               names, and a truncated response preview (1000 chars).
  #   "off"     — stores only outcome, model name, and response time.
  def chat_completion(messages, tools: [])
    uri = URI("#{@model_config[:base_url]}#{@model_config[:endpoint]}")
    body = {
      model: @model_config[:model],
      messages: messages,
      temperature: 0.7,
      max_tokens: @model_config[:max_tokens] || 2048,
      repetition_penalty: @model_config[:repetition_penalty] || 1.0
    }
    body[:tools] = tools if tools.present?

    request_json = body.to_json
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 60) do |http|
      http.post(uri, request_json, "Content-Type" => "application/json")
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

    unless response.is_a?(Net::HTTPSuccess)
      msg = "vLLM returned #{response.code}: #{response.body}"
      ApiEvent.log(service: "llm", action: "chat_completion", message: msg,
                   details: build_error_log(uri, response, request_json),
                   response_time_ms: elapsed_ms)
      raise LlmError, msg
    end

    parsed = JSON.parse(response.body)
    assistant_msg = parsed.dig("choices", 0, "message")
    tool_names = tools.map { |t| t.dig(:function, :name) }
    has_tool_calls = assistant_msg&.key?("tool_calls") && assistant_msg["tool_calls"].present?

    ApiEvent.log(service: "llm", action: "chat_completion", severity: "info", message: "OK",
                 details: build_success_log(uri, tool_names, has_tool_calls, assistant_msg,
                                            request_json, response.body),
                 response_time_ms: elapsed_ms)

    parsed
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    msg = "vLLM connection failed: #{e.class} — #{e.message}"
    Rails.logger.error("[vLLM] #{msg}")
    # Always log request on errors — this is the hardest case to debug without
    # knowing what was sent. Respects log_level for the request body.
    ApiEvent.log(service: "llm", action: "chat_completion", message: msg,
                 details: build_error_log(uri, nil, request_json),
                 response_time_ms: elapsed_ms)
    raise LlmError, msg
  rescue JSON::ParserError => e
    msg = "vLLM returned invalid JSON: #{e.message}"
    Rails.logger.error("[vLLM] #{msg}")
    ApiEvent.log(service: "llm", action: "chat_completion", message: msg,
                 details: build_error_log(uri, response, request_json),
                 response_time_ms: elapsed_ms)
    raise LlmError, msg
  end

  # Builds the api_events details hash for successful LLM calls.
  # What gets included depends on LLM_CONFIG[:log_level]:
  #
  #   "full"    — complete request body (all messages, tools, params) and
  #               complete response body. This is what you need to reproduce
  #               a bug: copy request_body, POST it with curl, compare.
  #
  #   "headers" — enough to understand the shape of the call without the bulk:
  #               how many messages, how big the payload was, which tools were
  #               offered, and a truncated preview of the response.
  #
  #   "off"     — just the model name and endpoint. Confirms a call happened.
  def build_success_log(uri, tool_names, has_tool_calls, assistant_msg, request_json, response_body)
    # Base details — always present regardless of log level.
    details = {
      endpoint: uri.to_s,
      model: @model_config[:model]
    }

    level = LLM_CONFIG[:log_level].to_s

    if level == "full"
      # Store the complete request and response as JSON strings. These can be
      # large (10-20KB each) but enable exact replay: paste request_body into
      # curl to reproduce. Parse response_body to see exactly what the model
      # returned, including token usage and finish_reason.
      details[:request_body] = request_json
      details[:response_body] = response_body
    end

    if level == "full" || level == "headers"
      # Metadata — lightweight summary for quick triage without reading the
      # full bodies. message_count tells you how long the conversation was.
      # request_bytes tells you if the payload was unusually large.
      # response_preview is the first 1000 chars of the assistant message.
      details[:message_count] = JSON.parse(request_json).fetch("messages", []).size rescue nil
      details[:request_bytes] = request_json.bytesize
      details[:response_bytes] = response_body.bytesize
      details[:tools_sent] = tool_names
      details[:tool_calls_returned] = has_tool_calls
      details[:response_preview] = assistant_msg&.slice("role", "content", "tool_calls").to_s.truncate(1000)
    end

    details
  end

  # Builds the api_events details hash for failed LLM calls (HTTP errors,
  # timeouts, JSON parse errors). Always includes the request body at "full"
  # level because errors are the hardest to debug without knowing what was sent.
  def build_error_log(uri, response, request_json)
    details = {
      endpoint: uri.to_s,
      exception: response ? nil : "timeout/connection",
      status: response&.code
    }

    level = LLM_CONFIG[:log_level].to_s

    if level == "full"
      details[:request_body] = request_json
      # Include the raw error response body — vLLM/sglang error messages
      # often contain the specific validation error (e.g. "Invalid control
      # character at position 271") that pinpoints the problem.
      details[:response_body] = response&.body&.truncate(5000)
    end

    if level == "full" || level == "headers"
      details[:message_count] = JSON.parse(request_json).fetch("messages", []).size rescue nil
      details[:request_bytes] = request_json&.bytesize
    end

    details.compact
  end

  # Fallback parser for tool calls embedded in content as XML tags or bare JSON.
  # Handles: <tool_call>...</tool_call>, <tools>...</tools>, and bare JSON with
  # "name" + "arguments" keys (some models skip the XML wrapper entirely).
  # Returns an array of tool_call hashes matching the OpenAI format, or nil.
  TOOL_CALL_PATTERN = /<tool_call>\s*(.*?)\s*<\/tool_call>|<tools>\s*(.*?)\s*<\/tools>/m

  # GLM sometimes emits ```action\nname\n{json}\n``` code blocks instead of
  # structured tool_calls or XML tags.
  ACTION_BLOCK_PATTERN = /```action\s*\n(\S+)\s*\n(.*?)```/m

  def parse_tool_calls_from_content(content)
    # Try XML-wrapped format first.
    matches = content.scan(TOOL_CALL_PATTERN)
    if matches.present?
      return build_calls_from_matches(matches)
    end

    # Try ```action``` code block format (GLM variant).
    action = parse_action_block(content)
    return action if action.present?

    # Try bare JSON: the entire content (or a line) is a JSON object with "name" + "arguments".
    bare = try_parse_bare_tool_call(content)
    bare.presence
  end

  # GLM sometimes emits tool calls as <tool_call>name<arg_key>k</arg_key><arg_value>v</arg_value></tool_call>
  # instead of JSON inside the tags. Detect and parse this format first.
  ARG_KV_PATTERN = /<arg_key>\s*(.*?)\s*<\/arg_key>\s*<arg_value>\s*(.*?)\s*<\/arg_value>/m

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
    # Extract tool name: text before the first <arg_key> tag.
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
