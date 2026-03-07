class Line::EventDispatchJob < ApplicationJob
  queue_as :default

  def perform(event_data)
    Line::EventRouter.call(event_data)
  end
end
