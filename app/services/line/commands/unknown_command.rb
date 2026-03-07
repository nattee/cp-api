class Line::Commands::UnknownCommand < Line::Commands::BaseCommand
  def execute(_args)
    reply("Unknown command. Send \"help\" for available commands.")
  end
end
