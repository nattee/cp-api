module LlmEval
  # Fires each eval case at a vLLM endpoint and scores the FIRST tool call
  # the model emits. Selection-only: tools are never executed, so candidate
  # definitions can be evaluated before their handlers exist and eval runs
  # can never touch data.
  #
  # Uses the production system prompt and temperature so results reflect
  # what LINE users actually experience; repeats measure sampling variance.
  class Runner
    REQUEST_TEMPERATURE = 0.7 # match LlmService#chat_completion

    def initialize(model_key:, definitions:, cases:, repeats: 3)
      @model_config = LLM_CONFIG[:models][model_key.to_sym] ||
                      raise(ArgumentError, "unknown model '#{model_key}' (keys: #{LLM_CONFIG[:models].keys.join(', ')})")
      @definitions = definitions
      @cases = cases
      @repeats = repeats
    end

    # Yields (result_hash) after each attempt for live progress output.
    def call
      results = []
      @cases.each do |kase|
        @repeats.times do |i|
          result = attempt(kase, i + 1)
          results << result
          yield result if block_given?
        end
      end
      results
    end

    private

    def attempt(kase, attempt_no)
      tool_call =
        begin
          first_tool_call(kase["question"])
        rescue StandardError => e
          return { case_id: kase["id"], group: kase["group"], attempt: attempt_no,
                   called_tool: "ERROR: #{e.class}", tool_ok: false, params_ok: false, misses: [] }
        end

      LlmEval::Scorer.score(kase, tool_call)
             .merge(case_id: kase["id"], group: kase["group"], attempt: attempt_no)
    end

    def first_tool_call(question)
      body = {
        model: @model_config[:model],
        messages: [
          { role: "system", content: LLM_CONFIG[:system_prompt] },
          { role: "user", content: question }
        ],
        temperature: REQUEST_TEMPERATURE,
        max_tokens: @model_config[:max_tokens] || 4096,
        tools: @definitions
      }

      uri = URI("#{@model_config[:base_url]}#{@model_config[:endpoint]}")
      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 120) do |http|
        http.post(uri, body.to_json, "Content-Type" => "application/json")
      end
      raise "vLLM returned #{response.code}: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)

      message = JSON.parse(response.body).dig("choices", 0, "message") || {}
      tool_calls = message["tool_calls"].presence ||
                   Line::ToolCallParser.parse(message["content"].to_s)
      tool_calls&.first
    end
  end
end
