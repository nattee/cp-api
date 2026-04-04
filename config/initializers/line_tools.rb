# Register all LINE chatbot tools with the ToolRegistry.
# Add new tools here as they are created.
#
# Uses `to_prepare` instead of `after_initialize` because Rails development
# mode reloads autoloaded classes on each request, which wipes ToolRegistry's
# @registry instance variable. `to_prepare` re-runs after every reload,
# keeping the registry populated. In production (eager loading), it runs once.
Rails.application.config.to_prepare do
  Line::ToolRegistry.register(
    "echo",
    definition: Line::Tools::EchoTool::DEFINITION,
    handler: Line::Tools::EchoTool
  )

  Line::ToolRegistry.register(
    "student_lookup",
    definition: Line::Tools::StudentLookupTool::DEFINITION,
    handler: Line::Tools::StudentLookupTool
  )
end
