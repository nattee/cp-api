# Central registry of tools available to the LLM.
# Each tool registers itself with a name, an OpenAI-format function definition,
# and a handler class that implements .call(arguments).
#
# Usage:
#   Line::ToolRegistry.register("echo", definition: { ... }, handler: Line::Tools::EchoTool)
#   Line::ToolRegistry.definitions   # => array of OpenAI tool objects for the API request
#   Line::ToolRegistry.handler_for("echo") # => Line::Tools::EchoTool
class Line::ToolRegistry
  class << self
    def register(name, definition:, handler:)
      registry[name] = { definition: definition, handler: handler }
    end

    # Returns the OpenAI-format tools array for the chat completions request.
    def definitions
      registry.map do |name, entry|
        {
          type: "function",
          function: { name: name }.merge(entry[:definition])
        }
      end
    end

    # Returns the handler class for a given tool name, or nil if not found.
    def handler_for(name)
      registry.dig(name, :handler)
    end

    def registered?(name)
      registry.key?(name)
    end

    def reset!
      @registry = {}
    end

    private

    def registry
      @registry ||= {}
    end
  end
end
