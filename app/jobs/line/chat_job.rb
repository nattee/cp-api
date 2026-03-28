# Async job that sends a LINE user's message through the LLM and delivers
# the response back via LINE. Enqueued by MessageRouter for any free-text
# (non-command) message.
#
# Reply tokens expire ~30 seconds after the webhook, so if the LLM takes
# longer we fall back to the push API (which requires no token but uses
# the monthly message quota).
class Line::ChatJob < ApplicationJob
  queue_as :default

  # LlmError wraps all vLLM failures (timeout, connection, bad response).
  # Don't retry — the user gets a "sorry" message immediately.
  discard_on Line::LlmService::LlmError

  def perform(line_user_id:, reply_token:, message:)
    user = User.find_by(provider: "line", uid: line_user_id)
    response = Line::LlmService.new(message, line_user_id: line_user_id, user: user).call

    deliver(reply_token, line_user_id, response)
  rescue Line::LlmService::LlmError => e
    Rails.logger.error("LLM error: #{e.message}")
    Line::ReplyService.push(line_user_id, "Sorry, I'm having trouble processing your request right now.")
  rescue => e
    Rails.logger.error("[ChatJob] Unexpected error: #{e.class}: #{e.message}")
    ApiEvent.log(source: "llm", message: "ChatJob failed: #{e.message}", details: { exception: e.class.name, line_user_id: line_user_id })
    Line::ReplyService.push(line_user_id, "Sorry, something went wrong. Please try again later.")
  end

  private

  # Tries the free reply API first; falls back to push if the token has expired.
  def deliver(reply_token, line_user_id, text)
    Line::ReplyService.reply(reply_token, text)
  rescue => e
    Rails.logger.info("Reply token expired, falling back to push: #{e.message}")
    Line::ReplyService.push(line_user_id, text)
  end
end
