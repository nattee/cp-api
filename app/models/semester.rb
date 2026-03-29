class Semester < ApplicationRecord
  SEMESTER_NUMBERS = [1, 2, 3].freeze
  SEMESTER_LABELS = { 1 => "First", 2 => "Second", 3 => "Summer" }.freeze

  has_many :course_offerings, dependent: :destroy
  has_many :scrapes, dependent: :destroy
  has_many :courses, through: :course_offerings

  validates :year_be, presence: true, numericality: { only_integer: true }
  validates :semester_number, presence: true, inclusion: { in: SEMESTER_NUMBERS }
  validates :year_be, uniqueness: { scope: :semester_number }

  scope :ordered, -> { order(year_be: :desc, semester_number: :desc) }

  def display_name
    "#{year_be}/#{semester_number}"
  end
end
