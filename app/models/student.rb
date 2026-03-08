class Student < ApplicationRecord
  STATUSES = %w[active graduated on_leave].freeze

  # Material Symbols icon for each status — used by Tom Select dropdowns
  # and anywhere else that needs a visual indicator for status.
  STATUS_ICONS = {
    "active"    => "check_circle",
    "graduated" => "school",
    "on_leave"  => "pause_circle"
  }.freeze

  validates :student_id, presence: true, uniqueness: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :admission_year, presence: true, numericality: { only_integer: true }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    "#{first_name} #{last_name}"
  end

  def full_name_th
    return nil if first_name_th.blank? && last_name_th.blank?
    "#{first_name_th} #{last_name_th}"
  end

  def active?
    status == "active"
  end

  def graduated?
    status == "graduated"
  end

  def on_leave?
    status == "on_leave"
  end
end
