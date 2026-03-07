class Line::EventRouter
  def self.call(event_data)
    case event_data["type"]
    when "message"
      Line::MessageRouter.call(event_data) if event_data.dig("message", "type") == "text"
    when "follow"
      Line::ReplyService.reply(
        event_data["reply_token"],
        "Welcome! Link your account by sending: link <your-code>\nGet a code at the LINE Account page in CP-API."
      )
    end
  end
end
