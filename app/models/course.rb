class Course < ApplicationRecord
  belongs_to :program
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error

  AUTO_GENERATED_LEVELS = %w[none copied placeholder].freeze

  AUTO_GENERATED_ICONS = {
    "none"        => nil,
    "copied"      => "content_copy",
    "placeholder" => "help_outline"
  }.freeze

  validates :name, presence: true
  validates :course_no, presence: true
  validates :revision_year, presence: true, numericality: { only_integer: true }
  validates :course_no, uniqueness: { scope: :revision_year, message: "already exists for this revision year" }
  validates :auto_generated, presence: true, inclusion: { in: AUTO_GENERATED_LEVELS }
  validates :credits, numericality: { only_integer: true, allow_nil: true }
  validates :l_credits, numericality: { only_integer: true, allow_nil: true }
  validates :nl_credits, numericality: { only_integer: true, allow_nil: true }
  validates :l_hours, numericality: { only_integer: true, allow_nil: true }
  validates :nl_hours, numericality: { only_integer: true, allow_nil: true }
  validates :s_hours, numericality: { only_integer: true, allow_nil: true }

  def auto_generated?
    auto_generated != "none"
  end
end
