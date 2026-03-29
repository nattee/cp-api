class CourseOffering < ApplicationRecord
  STATUSES = %w[planned confirmed cancelled].freeze
  STATUS_ICONS = {
    "planned"   => "schedule",
    "confirmed" => "check_circle",
    "cancelled" => "cancel"
  }.freeze

  belongs_to :course
  belongs_to :semester
  has_many :sections, dependent: :destroy
  has_many :time_slots, through: :sections
  has_many :teachings, through: :sections

  accepts_nested_attributes_for :sections, allow_destroy: true, reject_if: :all_blank

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :course_id, uniqueness: { scope: :semester_id,
    message: "is already offered in this semester" }
end
