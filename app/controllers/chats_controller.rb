class ChatsController < ApplicationController
  before_action :require_admin

  def show
    @messages = ChatMessage.recent_for(line_user_id)
  end

  def create
    message = params[:message].to_s.strip
    if message.blank?
      redirect_to chat_path
      return
    end

    # Handle slash commands using the same command classes as LINE.
    if message.start_with?("/")
      dispatch_command(message)
      return
    end

    Line::LlmService.new(message, line_user_id: line_user_id, user: current_user).call
    redirect_to chat_path
  rescue Line::LlmService::LlmError => e
    redirect_to chat_path, alert: "LLM error: #{e.message}"
  end

  private

  # Routes slash commands to the same handler classes used by LINE.
  # Only the delivery differs: LINE replies via ReplyService, web uses flash.
  def dispatch_command(message)
    parts = message.split(/\s+/, 2)
    command_key = parts[0].delete_prefix("/").downcase
    args = parts[1].to_s.strip

    handler_class = Line::MessageRouter::COMMAND_MAP[command_key]
    unless handler_class
      redirect_to chat_path, alert: "Unknown command: /#{command_key}. Type /help for available commands."
      return
    end

    context = { line_user_id: line_user_id, user: current_user, source: :web }
    cmd_result = handler_class.new(context).execute(args)

    if cmd_result.error?
      redirect_to chat_path, alert: cmd_result.text
    else
      redirect_to chat_path, notice: cmd_result.text
    end
  end

  def line_user_id
    "web_#{current_user.id}"
  end

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Not authorized."
    end
  end
end
