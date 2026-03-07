module LineBot
  def self.client
    @client ||= Line::Bot::V2::MessagingApi::ApiClient.new(
      channel_access_token: Rails.application.credentials.dig(:line, :channel_access_token)
    )
  end

  def self.channel_secret
    Rails.application.credentials.dig(:line, :channel_secret)
  end
end
