class Line::Commands::HelpCommand < Line::Commands::BaseCommand
  def execute(_args)
    lines = [
      "Available commands:",
      "  link <code> - Link your LINE account",
      "  model - Show or switch LLM model",
      "  clear - Clear conversation history",
      "  help - Show this message"
    ]
    reply(lines.join("\n"))
  end
end
