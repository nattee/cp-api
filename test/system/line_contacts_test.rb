require "application_system_test_case"

class LineContactsTest < ApplicationSystemTestCase
  setup do
    @contact = LineContact.create!(
      line_user_id: "U_SYS_CONTACT",
      display_name: "VIP Student",
      recent_messages: [
        { "text" => "Hello, is this CP department?", "at" => 5.minutes.ago.iso8601 },
        { "text" => "I'd like to know about enrollment", "at" => 3.minutes.ago.iso8601 }
      ],
      message_count: 2,
      first_seen_at: 5.minutes.ago,
      last_seen_at: 3.minutes.ago
    )

    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index shows unlinked contacts" do
    visit line_contacts_path
    assert_text "LINE Contacts"
    assert_text "VIP Student"
    assert_text "2"  # message count
  end

  test "show displays recent messages" do
    visit line_contact_path(@contact)
    assert_text "U_SYS_CONTACT"
    assert_text "Hello, is this CP department?"
    assert_text "I'd like to know about enrollment"
  end

  test "create and link flow" do
    visit line_contact_path(@contact)
    click_on "Create & Link"

    fill_in "Username", with: "vip_student"
    fill_in "Email", with: "vip@example.com"
    fill_in "Name", with: "VIP Student"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_on "Create & Link"

    assert_text "created and linked"

    user = User.find_by(username: "vip_student")
    assert_equal "line", user.provider
    assert_equal "U_SYS_CONTACT", user.uid
    assert user.llm_consent?
  end
end
