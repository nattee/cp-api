# Dummy tool for testing the tool-calling loop.
# Returns its arguments back as a JSON string.
class Line::Tools::EchoTool
  DEFINITION = {
    description: "Echo the provided arguments back. For testing only.",
    parameters: {
      type: "object",
      properties: {
        text: { type: "string", description: "Text to echo back" }
      },
      required: [ "text" ]
    }
  }.freeze

  def self.call(arguments)
    arguments.to_json
  end
end
