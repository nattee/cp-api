require "test_helper"

class LineContactTest < ActiveSupport::TestCase
  setup do
    @line_user_id = "U_CONTACT_TEST"
    LineContact.where(line_user_id: @line_user_id).delete_all
  end

  # --- Validations ---

  test "valid contact is valid" do
    contact = LineContact.new(line_user_id: @line_user_id, first_seen_at: Time.current, last_seen_at: Time.current)
    assert contact.valid?
  end

  test "requires line_user_id" do
    contact = LineContact.new(first_seen_at: Time.current, last_seen_at: Time.current)
    assert_not contact.valid?
    assert_includes contact.errors[:line_user_id], "can't be blank"
  end

  test "line_user_id must be unique" do
    LineContact.create!(line_user_id: @line_user_id, first_seen_at: Time.current, last_seen_at: Time.current)
    duplicate = LineContact.new(line_user_id: @line_user_id, first_seen_at: Time.current, last_seen_at: Time.current)
    assert_not duplicate.valid?
  end

  # --- record_message ---

  test "record_message creates new contact on first message" do
    result = LineContact.record_message(@line_user_id, "Hello")
    assert_equal :first_contact, result

    contact = LineContact.find_by(line_user_id: @line_user_id)
    assert_equal 1, contact.message_count
    assert_equal 1, contact.recent_messages.size
    assert_equal "Hello", contact.recent_messages.first["text"]
    assert contact.first_seen_at.present?
    assert contact.last_seen_at.present?
  end

  test "record_message updates existing contact" do
    LineContact.record_message(@line_user_id, "First")
    result = LineContact.record_message(@line_user_id, "Second")
    assert_equal :recorded, result

    contact = LineContact.find_by(line_user_id: @line_user_id)
    assert_equal 2, contact.message_count
    assert_equal 2, contact.recent_messages.size
    assert_equal "Second", contact.recent_messages.last["text"]
  end

  test "record_message truncates to MAX_RECENT_MESSAGES" do
    (LineContact::MAX_RECENT_MESSAGES + 3).times do |i|
      LineContact.record_message(@line_user_id, "Message #{i}")
    end

    contact = LineContact.find_by(line_user_id: @line_user_id)
    assert_equal LineContact::MAX_RECENT_MESSAGES, contact.recent_messages.size
    # Oldest messages should be dropped
    assert_equal "Message 3", contact.recent_messages.first["text"]
  end

  test "record_message truncates long messages" do
    long_text = "x" * 1000
    LineContact.record_message(@line_user_id, long_text)

    contact = LineContact.find_by(line_user_id: @line_user_id)
    assert_equal 500, contact.recent_messages.first["text"].length
  end

  # --- latest_message ---

  test "latest_message returns last message text" do
    LineContact.record_message(@line_user_id, "First")
    LineContact.record_message(@line_user_id, "Last")

    contact = LineContact.find_by(line_user_id: @line_user_id)
    assert_equal "Last", contact.latest_message
  end

  test "latest_message returns nil when no messages" do
    contact = LineContact.create!(line_user_id: @line_user_id, first_seen_at: Time.current, last_seen_at: Time.current)
    assert_nil contact.latest_message
  end

  # --- cleanup ---

  test "cleanup removes old contacts" do
    old = LineContact.create!(line_user_id: "U_OLD", first_seen_at: 60.days.ago, last_seen_at: 31.days.ago)
    recent = LineContact.create!(line_user_id: "U_RECENT", first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)

    LineContact.cleanup
    assert_not LineContact.exists?(old.id)
    assert LineContact.exists?(recent.id)
  end
end
