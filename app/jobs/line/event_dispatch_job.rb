class Line::EventDispatchJob < ApplicationJob
  queue_as :default

  def perform(event_data)
    Line::EventRouter.call(event_data)
  rescue => e
    Rails.logger.error("[EventDispatchJob] #{e.class}: #{e.message}")
    ApiEvent.log(
      service: "webhook",
      action: "dispatch",
      message: "Event dispatch failed: #{e.message}",
      details: { exception: e.class.name, event_type: event_data&.dig("type") }
    )
  end
end
