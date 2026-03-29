class ApiEvent < ApplicationRecord
  SERVICES = %w[line_reply line_push llm webhook].freeze
  SEVERITIES = %w[error warning info].freeze

  validates :service, inclusion: { in: SERVICES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :errors_since, ->(since) { where(severity: "error").where("created_at >= ?", since) }

  # Best-effort logging — never raises, even if DB is down.
  def self.log(service:, message:, severity: "error", action: nil, details: {}, response_time_ms: nil)
    create!(service: service, severity: severity, message: message, action: action, details: details, response_time_ms: response_time_ms)
  rescue => e
    Rails.logger.error("[ApiEvent] Failed to persist event: #{e.message} | service=#{service} message=#{message}")
  end

  # Wraps a block with timing. Yields, then logs an info event with elapsed ms.
  # If the block raises, the caller's own rescue handles the error event.
  def self.timed(service:, action: nil, details: {})
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    log(service: service, severity: "info", message: "OK", action: action, details: details, response_time_ms: elapsed_ms)
    result
  end

  def self.cleanup(older_than: 30.days.ago)
    where("created_at < ?", older_than).delete_all
  end
end
