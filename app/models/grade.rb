class Grade < ApplicationRecord
  belongs_to :student
  belongs_to :course

  GRADES = %w[A B+ B C+ C D+ D F S U I W V M P R X].freeze

  GRADE_WEIGHTS = {
    "A" => 4.0, "B+" => 3.5, "B" => 3.0, "C+" => 2.5,
    "C" => 2.0, "D+" => 1.5, "D" => 1.0, "F" => 0.0
  }.freeze

  SEMESTERS = [1, 2, 3].freeze
  SOURCES = %w[imported manual].freeze

  SOURCE_ICONS = {
    "imported" => "cloud_download",
    "manual"   => "edit_note"
  }.freeze

  validates :year, presence: true, numericality: { only_integer: true }
  validates :semester, presence: true, inclusion: { in: SEMESTERS }
  validates :grade, inclusion: { in: GRADES }, allow_nil: true
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :credits_grant, numericality: { only_integer: true }, allow_nil: true
  validates :student_id, uniqueness: { scope: [:course_id, :year, :semester],
                                       message: "is already enrolled in this course for this term" }

  scope :graded, -> { where.not(grade_weight: nil) }
  scope :for_term, ->(year, semester) { where(year: year, semester: semester) }

  def imported?
    source == "imported"
  end

  def manual?
    source == "manual"
  end

  def grade_badge_class
    return nil if grade.blank?
    "badge-grade-#{grade.downcase.gsub('+', '-plus')}"
  end
end
