module ChatMessagesHelper
  def render_chat_bubble(msg)
    render partial: "chat_messages/chat_bubble", locals: { msg: msg }
  end

  def render_tool_chain(msg, round_msgs)
    render partial: "chat_messages/tool_chain", locals: { msg: msg, round_msgs: round_msgs }
  end
end
