# Register all LINE chatbot tools with the ToolRegistry.
# Add new tools here as they are created.
Rails.application.config.after_initialize do
  Line::ToolRegistry.register(
    "echo",
    definition: Line::Tools::EchoTool::DEFINITION,
    handler: Line::Tools::EchoTool
  )
end
