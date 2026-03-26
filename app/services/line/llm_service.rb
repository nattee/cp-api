# Sends a user message to a vLLM instance (OpenAI-compatible API) and returns
# the assistant's text reply. Currently a single-round request/response;
# the tool-calling loop will be layered on top of this later.
class Line::LlmService
  class LlmError < StandardError; end

  def initialize(user_message, user: nil)
    @user_message = user_message
    @user = user # reserved for future per-user context
    @config = LLM_CONFIG
  end

  # Returns the assistant's reply as a plain String.
  def call
    messages = build_messages
    response = chat_completion(messages)
    extract_content(response)
  end

  private

  # Assembles the message array sent to the LLM.
  def build_messages
    messages = []
    messages << { role: "system", content: system_prompt } if system_prompt.present?
    messages << { role: "user", content: @user_message }
    messages
  end

  def system_prompt
    @config[:system_prompt]
  end

  # POSTs to the OpenAI-compatible /v1/chat/completions endpoint.
  # Raises LlmError on non-2xx responses.
  def chat_completion(messages)
    uri = URI("#{@config[:base_url]}#{@config[:endpoint]}")
    body = {
      model: @config[:model],
      messages: messages,
      temperature: 0.7
    }

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

  # Extracts the assistant message content from the OpenAI-format response.
  def extract_content(response)
    response.dig("choices", 0, "message", "content").to_s.strip
  end
end
