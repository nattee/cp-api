module LlmEval
  # Scores one model attempt against an eval case's accepted alternatives.
  # A case passes on tool selection when the called tool matches ANY accept
  # alternative; params are then checked against that alternative only.
  class Scorer
    def self.score(eval_case, tool_call)
      called = tool_call ? tool_call.dig("function", "name") : "none"
      args = extract_args(tool_call)

      eval_case["accept"].each do |alt|
        next unless alt["tool"] == called

        misses = (alt["params"] || {}).reject { |key, expected| param_match?(args[key], expected) }.keys
        return { called_tool: called, tool_ok: true, params_ok: misses.empty?, misses: misses }
      end

      { called_tool: called, tool_ok: false, params_ok: false, misses: [] }
    end

    def self.extract_args(tool_call)
      return {} unless tool_call

      raw = tool_call.dig("function", "arguments")
      raw.is_a?(String) ? JSON.parse(raw) : (raw || {})
    rescue JSON::ParserError
      {}
    end
    private_class_method :extract_args

    # Strings pass on case-insensitive CONTAINMENT — models legitimately send
    # "อ.ณัฐ" where the case expects "ณัฐ", or "ENG4-303" for "303". Non-strings
    # compare as normalized strings so YAML 2568 matches JSON "2568".
    def self.param_match?(actual, expected)
      return false if actual.nil?

      if expected.is_a?(String)
        actual.to_s.downcase.include?(expected.downcase)
      else
        actual.to_s.strip == expected.to_s
      end
    end
    private_class_method :param_match?
  end
end
