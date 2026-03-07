class Line::Commands::BaseCommand
  attr_reader :event_data

  def initialize(event_data)
    @event_data = event_data
  end

  def execute(args)
    raise NotImplementedError
  end

  private

  def line_user_id
    event_data.dig("source", "user_id")
  end

  def reply_token
    event_data["reply_token"]
  end

  def current_user
    @current_user ||= User.find_by(provider: "line", uid: line_user_id)
  end

  def linked?
    current_user.present?
  end

  def require_linked!
    unless linked?
      reply("Your LINE account is not linked. Link it first by sending: link <your-code>")
      throw :halt
    end
  end

  def reply(text)
    Line::ReplyService.reply(reply_token, text)
  end
end
