# Stores conversation history for LINE chatbot LLM interactions.
# Each row is one message (user, assistant, or tool) in a conversation.
class ChatMessage < ApplicationRecord
  HISTORY_LIMIT = 40
  EXPIRY = 24.hours

  validates :line_user_id, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant tool] }

  # Recent messages for a LINE user, oldest first, within the expiry window.
  scope :recent_for, ->(line_user_id) {
    where(line_user_id: line_user_id)
      .where(created_at: EXPIRY.ago..)
      .order(created_at: :asc)
      .last(HISTORY_LIMIT)
  }

  # Converts a stored record to the hash format expected by the OpenAI API.
  def to_llm_message
    msg = { "role" => role, "content" => content }
    msg["tool_calls"] = tool_calls if tool_calls.present?
    msg["tool_call_id"] = tool_call_id if tool_call_id.present?
    msg
  end
end
