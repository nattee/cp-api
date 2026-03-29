# Thin wrapper around the LINE Messaging API for sending text messages.
# Two delivery methods:
#   reply  — uses the reply token (free, but expires ~30s after webhook)
#   push   — uses the user ID (counts against monthly quota, but never expires)
class Line::ReplyService
  # Send a reply using the webhook's reply token (free, must be used quickly).
  def self.reply(reply_token, text)
    message = ::Line::Bot::V2::MessagingApi::TextMessage.new(text: text)
    request = ::Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: reply_token,
      messages: [message]
    )
    ApiEvent.timed(service: "line_reply", action: "reply") do
      LineBot.client.reply_message(reply_message_request: request)
    end
  rescue => e
    Rails.logger.error("[LINE Reply] #{e.class}: #{e.message}")
    ApiEvent.log(service: "line_reply", action: "reply", message: "Reply failed: #{e.message}", details: { exception: e.class.name })
    raise
  end

  # Send a message using the user's LINE ID (works any time, uses quota).
  def self.push(user_id, text)
    message = ::Line::Bot::V2::MessagingApi::TextMessage.new(text: text)
    request = ::Line::Bot::V2::MessagingApi::PushMessageRequest.new(
      to: user_id,
      messages: [message]
    )
    ApiEvent.timed(service: "line_push", action: "push", details: { user_id: user_id }) do
      LineBot.client.push_message(push_message_request: request)
    end
  rescue => e
    Rails.logger.error("[LINE Push] #{e.class}: #{e.message}")
    ApiEvent.log(service: "line_push", action: "push", message: "Push to #{user_id} failed: #{e.message}", details: { exception: e.class.name, user_id: user_id })
    raise
  end
end
