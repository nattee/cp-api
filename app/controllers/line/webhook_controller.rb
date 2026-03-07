class Line::WebhookController < ActionController::API
  def callback
    body = request.body.read
    signature = request.env["HTTP_X_LINE_SIGNATURE"]

    unless webhook_parser.verify_signature(body: body, signature: signature.to_s)
      head :bad_request
      return
    end

    events = JSON.parse(body).fetch("events", [])
    events.each do |event_hash|
      Line::EventDispatchJob.perform_later(normalize_keys(event_hash))
    end

    head :ok
  end

  private

  def webhook_parser
    @webhook_parser ||= ::Line::Bot::V2::WebhookParser.new(
      channel_secret: LineBot.channel_secret
    )
  end

  def normalize_keys(hash)
    hash.deep_transform_keys { |key| key.to_s.underscore }
  end
end
