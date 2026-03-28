class ApiEvent < ApplicationRecord
  SOURCES = %w[line_reply line_push llm webhook].freeze
  SEVERITIES = %w[error warning].freeze

  validates :source, inclusion: { in: SOURCES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :errors_since, ->(since) { where(severity: "error").where("created_at >= ?", since) }

  # Best-effort logging — never raises, even if DB is down.
  def self.log(source:, message:, severity: "error", details: {})
    create!(source: source, severity: severity, message: message, details: details)
  rescue => e
    Rails.logger.error("[ApiEvent] Failed to persist event: #{e.message} | source=#{source} message=#{message}")
  end
end
