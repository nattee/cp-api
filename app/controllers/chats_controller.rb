class ChatsController < ApplicationController
  before_action :require_admin

  def show
    @messages = ChatMessage.recent_for(line_user_id)
    @tool_rounds = session.delete(:last_tool_rounds) || []
  end

  def create
    message = params[:message].to_s.strip
    if message.blank?
      redirect_to chat_path
      return
    end

    if message == "/clear"
      ChatMessage.where(line_user_id: line_user_id).delete_all
      redirect_to chat_path, notice: "Chat history cleared."
      return
    end

    result = Line::LlmService.new(message, line_user_id: line_user_id, user: current_user).call
    session[:last_tool_rounds] = result.tool_rounds if result.tool_rounds.any?
    redirect_to chat_path
  rescue Line::LlmService::LlmError => e
    redirect_to chat_path, alert: "LLM error: #{e.message}"
  end

  private

  def line_user_id
    "web_#{current_user.id}"
  end

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Not authorized."
    end
  end
end
