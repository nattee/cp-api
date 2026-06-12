require "test_helper"

class Line::Commands::LinkCommandTest < ActiveSupport::TestCase
  setup do
    @user = users(:viewer)
    @line_user_id = "U_LINE_TEST_123"
  end

  test "links user when token is valid and not expired" do
    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    result = execute_command(token)

    assert_not result.error?
    assert_match(/Linked successfully/, result.text)

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

    result = execute_command(token)

    assert result.error?
    assert_match(/expired/, result.text)
    assert_nil @user.reload.provider
  end

  test "rejects invalid token" do
    result = execute_command("INVALID")

    assert result.error?
    assert_match(/Invalid/, result.text)
  end

  test "rejects blank token" do
    result = execute_command("")

    assert result.error?
    assert_match(/Usage/, result.text)
  end

  test "token cannot be reused after linking" do
    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    execute_command(token)
    assert_equal "line", @user.reload.provider

    # Second attempt with the same token by a different LINE user
    result = execute_command(token, line_user_id: "U_OTHER")

    assert result.error?
    assert_match(/Invalid/, result.text)
  end

  test "rejects if LINE account is already linked to another user" do
    # Link the LINE account to admin first
    users(:admin).update!(provider: "line", uid: @line_user_id)

    token = "ABCD1234"
    @user.update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    result = execute_command(token)

    assert result.error?
    assert_match(/already linked/, result.text)
  end

  test "quick-linked user cannot use a link code meant for another user" do
    # Admin quick-linked this LINE account to viewer
    @user.update!(provider: "line", uid: @line_user_id, llm_consent: true)

    # Editor has a pending link code
    token = "WXYZ5678"
    users(:editor).update!(line_link_token: token, line_link_token_expires_at: 24.hours.from_now)

    # LINE user tries to use editor's code — should be rejected because already linked
    result = execute_command(token)

    assert result.error?
    assert_match(/already linked/, result.text)
    # Editor's code should not be consumed
    assert_equal token, users(:editor).reload.line_link_token
  end

  private

  # Builds context the same way MessageRouter.build_context does: the user is
  # whoever is already linked to this LINE account, nil otherwise.
  def execute_command(token, line_user_id: @line_user_id)
    context = {
      line_user_id: line_user_id,
      user: User.find_by(provider: "line", uid: line_user_id),
      source: :line
    }
    Line::Commands::LinkCommand.new(context).execute(token)
  end
end
