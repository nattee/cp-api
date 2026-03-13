class Course < ApplicationRecord
  belongs_to :program

  validates :name, presence: true
  validates :course_no, presence: true
  validates :revision_year, presence: true, numericality: { only_integer: true }
  validates :course_no, uniqueness: { scope: :revision_year, message: "already exists for this revision year" }
  validates :credits, numericality: { only_integer: true, allow_nil: true }
  validates :l_credits, numericality: { only_integer: true, allow_nil: true }
  validates :nl_credits, numericality: { only_integer: true, allow_nil: true }
  validates :l_hours, numericality: { only_integer: true, allow_nil: true }
  validates :nl_hours, numericality: { only_integer: true, allow_nil: true }
  validates :s_hours, numericality: { only_integer: true, allow_nil: true }
end
