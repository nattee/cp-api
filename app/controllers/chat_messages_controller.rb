class ChatMessagesController < ApplicationController
  before_action :require_admin

  def index
    @conversations = ChatMessage
      .select("line_user_id, COUNT(*) AS message_count, MAX(created_at) AS last_activity")
      .group(:line_user_id)
      .order("last_activity DESC")

    # Build a lookup of line_user_id → user for linked accounts
    line_user_ids = @conversations.map(&:line_user_id)
    @linked_users = User.where(provider: "line", uid: line_user_ids).index_by(&:uid)
  end

  def show
    @line_user_id = params[:id]
    @messages = ChatMessage.where(line_user_id: @line_user_id).order(created_at: :asc)
    @linked_user = User.find_by(provider: "line", uid: @line_user_id)
    @debug_mode = current_user.debug_tool_calls?

    redirect_to chat_messages_path, alert: "No messages found for this user." if @messages.empty?
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can access chat history."
    end
  end
end
