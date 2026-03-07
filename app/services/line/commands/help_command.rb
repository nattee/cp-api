class Line::Commands::HelpCommand < Line::Commands::BaseCommand
  def execute(_args)
    lines = [
      "Available commands:",
      "  link <code> - Link your LINE account",
      "  help - Show this message"
    ]
    reply(lines.join("\n"))
  end
end
