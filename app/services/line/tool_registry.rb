# Central registry of tools available to the LLM.
# Each tool registers itself with a name, an OpenAI-format function definition,
# a handler class that implements .call(arguments, user: nil), and the
# permission key required to call it.
#
# Usage:
#   Line::ToolRegistry.register("search", definition: { ... }, handler: Line::Tools::SearchTool, permission: "courses.read")
#   Line::ToolRegistry.definitions   # => array of OpenAI tool objects for the API request
#   Line::ToolRegistry.handler_for("search") # => Line::Tools::SearchTool
class Line::ToolRegistry
  class << self
    def register(name, definition:, handler:, permission:)
      registry[name] = { definition: definition, handler: handler, permission: permission }
    end

    # OpenAI-format tools array, filtered to what this user's role permits —
    # the LLM never sees tools the user can't call (gate 1: keeps weak local
    # models from attempting doomed calls and the prompt small). nil user =
    # unfiltered: the admin web playground and the offline eval harness.
    def definitions(user: nil)
      registry.filter_map do |name, entry|
        next if user && !user.can?(entry[:permission])
        {
          type: "function",
          function: { name: name }.merge(entry[:definition])
        }
      end
    end

    # Gate 2 lookup (see ToolExecutor): the permission a tool call must hold.
    def required_permission_for(name)
      registry.dig(name, :permission)
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
