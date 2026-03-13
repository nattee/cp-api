class Program < ApplicationRecord
  DEGREE_LEVELS = %w[bachelor master doctoral].freeze

  DEGREE_LEVEL_ICONS = {
    "bachelor" => "school",
    "master"   => "psychology",
    "doctoral" => "science"
  }.freeze

  has_many :courses, dependent: :restrict_with_error
  has_many :students, dependent: :restrict_with_error

  validates :name_en, presence: true
  validates :degree_level, presence: true, inclusion: { in: DEGREE_LEVELS }
  validates :degree_name, presence: true
  validates :field_of_study, presence: true
  validates :year_started, presence: true, numericality: { only_integer: true }
end
