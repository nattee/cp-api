class Line::Commands::LinkCommand < Line::Commands::BaseCommand
  def execute(args)
    token = args.strip

    if token.blank?
      return error("Usage: /link <your-code>\nGet a code from the LINE Account page in CP-API.")
    end

    if current_user
      return error("Your LINE account is already linked to #{current_user.name}.")
    end

    user = User.find_by(line_link_token: token)

    if user.nil? || user.line_link_token_expires_at&.past?
      return error("Invalid or expired code. Please generate a new one.")
    end

    user.update!(
      provider: "line",
      uid: line_user_id,
      llm_consent: true,
      line_link_token: nil,
      line_link_token_expires_at: nil
    )

    result("Linked successfully! Your LINE account is now linked to #{user.name}.")
  end
end
