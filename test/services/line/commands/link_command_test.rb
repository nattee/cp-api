require "test_helper"

class Line::Commands::LinkCommandTest < ActiveSupport::TestCase
  setup do
    @user = users(:viewer)
    @line_user_id = "U_LINE_TEST_123"
    @event_data = {
      "source" => { "user_id" => @line_user_id },
      "reply_token" => "test_reply_token",
      "message" => { "text" => "link TOKEN" }
    }
  end

  test "links user when token is valid and not expired" do
    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    execute_command(token)

    @user.reload
    assert_equal "line", @user.provider
    assert_equal @line_user_id, @user.uid
    assert @user.llm_consent
    assert_nil @user.line_link_token
    assert_nil @user.line_link_token_expires_at
  end

  test "rejects expired token" do
    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    travel 25.hours

    reply_text = execute_command(token)

    assert_match(/expired/, reply_text)
    assert_nil @user.reload.provider
  end

  test "rejects invalid token" do
    reply_text = execute_command("INVALID")

    assert_match(/Invalid/, reply_text)
  end

  test "rejects blank token" do
    reply_text = execute_command("")

    assert_match(/Usage/, reply_text)
  end

  test "token cannot be reused after linking" do
    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    execute_command(token)
    assert_equal "line", @user.reload.provider

    # Second attempt with the same token by a different LINE user
    other_event = @event_data.merge("source" => { "user_id" => "U_OTHER" })
    cmd = Line::Commands::LinkCommand.new(other_event)
    reply_text = nil
    cmd.define_singleton_method(:reply) { |text| reply_text = text }
    cmd.execute(token)

    assert_match(/Invalid/, reply_text)
  end

  test "rejects if LINE account is already linked to another user" do
    # Link the LINE account to admin first
    users(:admin).update!(provider: "line", uid: @line_user_id)

    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    reply_text = execute_command(token)

    assert_match(/already linked/, reply_text)
  end

  test "quick-linked user cannot use a link code meant for another user" do
    # Admin quick-linked this LINE account to viewer
    @user.update!(provider: "line", uid: @line_user_id, llm_consent: true)

    # Editor has a pending link code
    token = "WXYZ5678"
    users(:editor).update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    # LINE user tries to use editor's code — should be rejected because already linked
    reply_text = execute_command(token)

    assert_match(/already linked/, reply_text)
    # Editor's code should not be consumed
    assert_equal token, users(:editor).reload.line_link_token
  end

  private

  def execute_command(token)
    cmd = Line::Commands::LinkCommand.new(@event_data)
    replied_text = nil
    cmd.define_singleton_method(:reply) { |text| replied_text = text }
    cmd.execute(token)
    replied_text
  end
end
