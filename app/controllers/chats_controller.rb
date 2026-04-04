class ChatsController < ApplicationController
  before_action :require_admin

  def show
    @messages = ChatMessage.recent_for(line_user_id)
    # Reconstruct tool rounds from the message history instead of session
    # (session is cookie-based with a 4KB limit — tool results easily overflow).
    # Find the last assistant text message and collect any tool rounds before it.
    @tool_rounds = extract_tool_rounds(@messages)
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

  # Extracts tool-call rounds from message history for display in the chat UI.
  # Walks backwards from the last message: if the last assistant message was
  # preceded by tool-call rounds (assistant with tool_calls → tool results),
  # collect them. Returns an array of hashes matching the view's expected format.
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

  def extract_tool_rounds(messages)
    return [] if messages.size < 3

    # Only show tool rounds for the most recent assistant response.
    last_msg = messages.last
    return [] unless last_msg.role == "assistant" && last_msg.tool_calls.blank?

    rounds = []
    i = messages.size - 2
    # Walk backwards collecting tool → assistant(tool_calls) pairs.
    while i >= 0
      msg = messages[i]
      if msg.role == "tool"
        tool_result = msg.content
        # The assistant(tool_calls) should be right before the tool message(s).
        j = i - 1
        j -= 1 while j >= 0 && messages[j].role == "tool"
        if j >= 0 && messages[j].role == "assistant" && messages[j].tool_calls.present?
          messages[j].tool_calls.each do |tc|
            fn = tc.is_a?(Hash) ? (tc["function"] || tc[:function]) : nil
            next unless fn
            rounds.unshift({
              tool: fn["name"] || fn[:name],
              arguments: fn["arguments"] || fn[:arguments],
              result: tool_result
            })
          end
          i = j - 1
        else
          break
        end
      else
        break
      end
    end

    rounds
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
