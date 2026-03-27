class Line::Commands::LinkCommand < Line::Commands::BaseCommand
  def execute(args)
    token = args.strip

    if token.blank?
      reply("Usage: link <your-code>\nGet a code from the LINE Account page in CP-API.")
      return
    end

    if linked?
      reply("Your LINE account is already linked to #{current_user.name}.")
      return
    end

    user = User.find_by(line_link_token: token)

    if user.nil? || user.line_link_token_expires_at&.past?
      reply("Invalid or expired code. Please generate a new one.")
      return
    end

    user.update!(
      provider: "line",
      uid: line_user_id,
      llm_consent: true,
      line_link_token: nil,
      line_link_token_expires_at: nil
    )

    reply("Linked successfully! Your LINE account is now linked to #{user.name}.")
  end
end
