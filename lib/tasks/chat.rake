# Quick console chat for testing the LLM tool-calling loop.
# Usage:
#   bin/rails "chat[hello]"
#   bin/rails "chat[ขอข้อมูลนิสิต 6732100021]"
#   bin/rails "chat[clear]"          # wipe console history
desc "Send a message to the LLM chatbot (for testing)"
task :chat, [:message] => :environment do |_t, args|
  line_user_id = "console"
  message = args[:message].to_s.strip

  if message.blank?
    puts "Usage: bin/rails \"chat[your message here]\""
    next
  end

  if message == "clear"
    ChatMessage.where(line_user_id: line_user_id).delete_all
    puts "Console chat history cleared."
    next
  end

  user = User.find(1) # superadmin
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
