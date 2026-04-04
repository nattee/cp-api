class LineContact < ApplicationRecord
  MAX_RECENT_MESSAGES = 10
  RATE_LIMIT_PER_HOUR = 20
  EXPIRY = 30.days

  validates :line_user_id, presence: true, uniqueness: true
  validates :first_seen_at, presence: true
  validates :last_seen_at, presence: true

  scope :recent, -> { order(last_seen_at: :desc) }

  # Records an incoming message from an unlinked LINE user.
  # Upserts the contact and appends the message to recent_messages.
  # Returns nil if rate-limited.
  def self.record_message(line_user_id, text)
    contact = find_or_initialize_by(line_user_id: line_user_id)
    now = Time.current

    if contact.persisted? && contact.rate_limited?
      return nil
    end

    first_contact = contact.new_record?
    contact.first_seen_at ||= now
    contact.last_seen_at = now
    contact.message_count += 1

    messages = contact.recent_messages || []
    messages << { "text" => text.truncate(500), "at" => now.iso8601 }
    contact.recent_messages = messages.last(MAX_RECENT_MESSAGES)

    contact.save!
    first_contact ? :first_contact : :recorded
  end

  def rate_limited?
    return false if message_count < RATE_LIMIT_PER_HOUR

    # Count messages in the last hour from recent_messages timestamps
    one_hour_ago = 1.hour.ago
    recent = (recent_messages || []).count { |m| Time.parse(m["at"]) > one_hour_ago rescue false }
    recent >= RATE_LIMIT_PER_HOUR
  end

  def latest_message
    recent_messages&.last&.dig("text")
  end

  def self.cleanup(older_than: EXPIRY.ago)
    where("last_seen_at < ?", older_than).delete_all
  end
end
