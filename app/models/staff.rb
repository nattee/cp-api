class Staff < ApplicationRecord
  STAFF_TYPES = %w[lecturer adjunct lab admin_permanent admin_annual admin_short_term].freeze

  STAFF_TYPE_ICONS = {
    "lecturer"         => "person",
    "adjunct"          => "person_add",
    "lab"              => "science",
    "admin_permanent"  => "badge",
    "admin_annual"     => "event_repeat",
    "admin_short_term" => "hourglass_bottom"
  }.freeze

  STATUSES = %w[active retired on_leave].freeze

  STATUS_ICONS = {
    "active"  => "check_circle",
    "retired" => "exit_to_app",
    "on_leave" => "pause_circle"
  }.freeze

  TITLES = %w[นาย นาง นางสาว].freeze

  ACADEMIC_TITLES = ["ศ.ดร.", "รศ.ดร.", "รศ.", "ผศ.ดร.", "ผศ.", "อ.ดร.", "ดร.", "อ."].freeze

  has_many :staff_programs, dependent: :destroy
  has_many :programs, through: :staff_programs

  validates :title, presence: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :staff_type, presence: true, inclusion: { in: STAFF_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    "#{first_name} #{last_name}"
  end

  def full_name_th
    return nil if first_name_th.blank? && last_name_th.blank?
    "#{first_name_th} #{last_name_th}"
  end

  def display_name
    parts = []
    parts << academic_title if academic_title.present?
    parts << full_name
    parts.join(" ")
  end

  def display_name_th
    return display_name if first_name_th.blank? && last_name_th.blank?
    parts = []
    parts << academic_title if academic_title.present?
    parts << full_name_th
    parts.join("")
  end

  def active?
    status == "active"
  end

  def retired?
    status == "retired"
  end

  def on_leave?
    status == "on_leave"
  end
end
