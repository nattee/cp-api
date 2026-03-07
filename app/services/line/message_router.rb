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

    command_class = COMMAND_MAP.fetch(command_key, Line::Commands::UnknownCommand)
    command_class.new(event_data).execute(args)
  end
end
