class LineAccountsController < ApplicationController
  def show
    @linked = current_user.provider == "line" && current_user.uid.present?
    @token = current_user.line_link_token if current_user.line_link_token_expires_at&.future?
  end

  def create
    token = SecureRandom.hex(16)
    current_user.update!(
      line_link_token: token,
      line_link_token_expires_at: 30.minutes.from_now
    )
    redirect_to line_account_path, notice: "Linking code generated. Send \"link #{token}\" to the LINE bot within 30 minutes."
  end

  def destroy
    current_user.update!(provider: nil, uid: nil)
    redirect_to line_account_path, notice: "LINE account unlinked."
  end
end
