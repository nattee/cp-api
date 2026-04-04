# Quick console chat for testing the LLM tool-calling loop.
# Usage:
#   bin/rails "chat[hello]"
#   bin/rails "chat[ขอข้อมูลนิสิต 6732100021]"
#   bin/rails "chat[clear]"          # wipe console history
#   USER=3 bin/rails "chat[hello]"   # use a specific user's model preference
desc "Send a message to the LLM chatbot (for testing)"
task :chat, [:message] => :environment do |_t, args|
  user_id = ENV.fetch("USER", 1)
  user = User.find(user_id)
  line_user_id = "console_#{user.id}"
  message = args[:message].to_s.strip

  if message.blank?
    puts "Usage: bin/rails \"chat[your message here]\""
    puts "       USER=3 bin/rails \"chat[hello]\"  # use a specific user"
    next
  end

  if message == "clear"
    ChatMessage.where(line_user_id: line_user_id).delete_all
    puts "Console chat history cleared."
    next
  end

  puts "User: #{user.name} (#{user.llm_model.presence || "default model"})"
  result = Line::LlmService.new(message, line_user_id: line_user_id, user: user).call

  if result.tool_rounds.any?
    puts "--- Tool Calls ---"
    result.tool_rounds.each do |round|
      puts "  [Round #{round[:round]}] #{round[:tool]}(#{round[:arguments]})"
      puts "  => #{round[:result].truncate(500)}"
      puts
    end
    puts "--- Reply ---"
  end

  puts result.reply
end
