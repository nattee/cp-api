# Routes incoming LINE text messages to either a slash command or the LLM.
# Recognized commands (link, help) are handled synchronously within the job.
# Everything else is dispatched to ChatJob for async LLM processing.
class Line::MessageRouter
  COMMAND_MAP = {
    "link" => Line::Commands::LinkCommand,
    "help" => Line::Commands::HelpCommand
  }.freeze

  def self.call(event_data)
    text = event_data.dig("message", "text").to_s.strip
    parts = text.split(/\s+/, 2)
    command_key = parts[0].to_s.downcase
    args = parts[1].to_s

    if COMMAND_MAP.key?(command_key)
      COMMAND_MAP[command_key].new(event_data).execute(args)
    else
      dispatch_to_llm(event_data, text)
    end
  end

  # Enqueue a ChatJob so the LLM call doesn't block the current job.
  def self.dispatch_to_llm(event_data, text)
    Line::ChatJob.perform_later(
      line_user_id: event_data.dig("source", "user_id"),
      reply_token: event_data["reply_token"],
      message: text
    )
  end
  private_class_method :dispatch_to_llm
end
