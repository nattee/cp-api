class Line::ReplyService
  def self.reply(reply_token, text)
    message = ::Line::Bot::V2::MessagingApi::TextMessage.new(text: text)
    request = ::Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: reply_token,
      messages: [message]
    )
    LineBot.client.reply_message(reply_message_request: request)
  end
end
