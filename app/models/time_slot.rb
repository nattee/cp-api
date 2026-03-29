class TimeSlot < ApplicationRecord
  DAYS_OF_WEEK = (0..6).to_a.freeze
  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  DAY_ABBRS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  belongs_to :section
  belongs_to :room, optional: true

  validates :day_of_week, presence: true, inclusion: { in: DAYS_OF_WEEK }
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time

  def day_name = DAY_NAMES[day_of_week]
  def day_abbr = DAY_ABBRS[day_of_week]
  def time_range = "#{start_time.strftime('%H:%M')}-#{end_time.strftime('%H:%M')}"

  private

  def end_time_after_start_time
    return unless start_time && end_time
    errors.add(:end_time, "must be after start time") if end_time <= start_time
  end
end
