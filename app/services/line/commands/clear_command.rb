# Clears the user's LLM conversation history.
class Line::Commands::ClearCommand < Line::Commands::BaseCommand
  def execute(_args)
    deleted = ChatMessage.where(line_user_id: line_user_id).delete_all
    result("Conversation cleared (#{deleted} messages removed).")
  end
end
