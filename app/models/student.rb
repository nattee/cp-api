class Student < ApplicationRecord
  SEXES = %w[M F].freeze
  STATUSES = %w[active graduated on_leave retired].freeze
  TCAS_ROUNDS = %w[TCAS1 TCAS2 TCAS3 TCAS4 other unknown].freeze

  # Material Symbols icon for each status — used by Select2 dropdowns
  # and anywhere else that needs a visual indicator for status.
  STATUS_ICONS = {
    "active"    => "check_circle",
    "graduated" => "school",
    "on_leave"  => "pause_circle",
    "retired"   => "exit_to_app"
  }.freeze

  belongs_to :program
  has_many :grades, dependent: :destroy

  validates :student_id, presence: true, uniqueness: true
  validates :first_name_th, presence: true
  validates :last_name_th, presence: true
  validates :admission_year_be, presence: true, numericality: { only_integer: true }
  validates :sex, inclusion: { in: SEXES }, allow_nil: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :tcas, inclusion: { in: TCAS_ROUNDS }, allow_nil: true

  scope :active, -> { where(status: "active") }

  def full_name
    "#{first_name} #{last_name}"
  end

  def full_name_th
    return nil if first_name_th.blank? && last_name_th.blank?
    "#{first_name_th} #{last_name_th}"
  end

  # Prefer Thai name for display; fall back to English
  def display_name
    full_name_th.presence || full_name
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

  def retired?
    status == "retired"
  end

  def gpa
    graded = grades.joins(:course).where.not(grade_weight: nil)
    total_weighted = graded.sum("grades.grade_weight * courses.credits")
    total_credits = graded.sum("courses.credits")
    total_credits.zero? ? nil : (total_weighted / total_credits).round(2)
  end

  def total_credits
    grades.joins(:course).where.not(grade_weight: nil).sum("courses.credits")
  end
end
