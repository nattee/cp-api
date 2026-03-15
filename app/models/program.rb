class Program < ApplicationRecord
  DEGREE_LEVELS = %w[bachelor master doctoral].freeze

  DEGREE_LEVEL_ICONS = {
    "bachelor" => "school",
    "master"   => "psychology",
    "doctoral" => "science"
  }.freeze

  PLACEHOLDER_NAME = "Unknown Program".freeze

  has_many :courses, dependent: :restrict_with_error
  has_many :students, dependent: :restrict_with_error

  validates :name_en, presence: true
  validates :degree_level, presence: true, inclusion: { in: DEGREE_LEVELS }
  validates :degree_name, presence: true
  validates :field_of_study, presence: true
  validates :year_started, presence: true, numericality: { only_integer: true }

  def self.placeholder
    find_or_create_by!(name_en: PLACEHOLDER_NAME) do |p|
      p.degree_level = "bachelor"
      p.degree_name = "Unknown"
      p.field_of_study = "Unknown"
      p.year_started = 0
    end
  end

  def placeholder?
    name_en == PLACEHOLDER_NAME
  end
end
