# Routes incoming LINE text messages to either a slash command or the LLM.
# Recognized commands are handled synchronously within the job.
# Everything else is dispatched to ChatJob for async LLM processing.
#
# Command routing rules:
#   - "help" works with or without slash (natural to type as bare word)
#   - All other commands require a "/" prefix (/clear, /model, /link)
#   - Any message starting with "/" that doesn't match a known command
#     gets an "unknown command" reply instead of being sent to the LLM.
#     This prevents typos like "/clera" from wasting an LLM call and
#     confusing the conversation history.
class Line::MessageRouter
  # Maps command names (without slash) to their handler classes.
  COMMAND_MAP = {
    "link" => Line::Commands::LinkCommand,
    "help" => Line::Commands::HelpCommand,
    "clear" => Line::Commands::ClearCommand,
    "model" => Line::Commands::ModelCommand
  }.freeze

  # Commands that work without the "/" prefix. Keep this minimal —
  # bare words are ambiguous and could be part of a normal conversation.
  BARE_COMMANDS = %w[help].freeze

  def self.call(event_data)
    text = event_data.dig("message", "text").to_s.strip
    first_word = text.split(/\s+/, 2)[0].to_s.downcase
    args = text.split(/\s+/, 2)[1].to_s
    reply_token = event_data["reply_token"]

    if first_word.start_with?("/")
      command_key = first_word.delete_prefix("/")
      if COMMAND_MAP.key?(command_key)
        context = build_context(event_data)
        result = COMMAND_MAP[command_key].new(context).execute(args)
        Line::ReplyService.reply(reply_token, result.text)
      else
        Line::ReplyService.reply(reply_token, "Unknown command: #{first_word}\nType /help to see available commands.")
      end
    elsif BARE_COMMANDS.include?(first_word)
      context = build_context(event_data)
      result = COMMAND_MAP[first_word].new(context).execute(args)
      Line::ReplyService.reply(reply_token, result.text)
    else
      dispatch_to_llm(event_data, text)
    end
  end

  def self.build_context(event_data)
    line_user_id = event_data.dig("source", "user_id")
    user = User.find_by(provider: "line", uid: line_user_id)
    { line_user_id: line_user_id, user: user, source: :line }
  end
  private_class_method :build_context

  # Enqueue a ChatJob so the LLM call doesn't block the current job.
  # Checks llm_consent before dispatching — unlinked or non-consenting users
  # are recorded as LineContact for admin review.
  def self.dispatch_to_llm(event_data, text)
    line_user_id = event_data.dig("source", "user_id")
    reply_token = event_data["reply_token"]
    user = User.find_by(provider: "line", uid: line_user_id)

    unless user&.llm_consent?
      result = LineContact.record_message(line_user_id, text)
      if result == :first_contact
        Line::ReplyService.reply(reply_token, "Thanks for your message! An admin will set up your account shortly.")
      end
      return
    end

    Line::ChatJob.perform_later(
      line_user_id: line_user_id,
      reply_token: reply_token,
      message: text
    )
  end
  private_class_method :dispatch_to_llm
end
