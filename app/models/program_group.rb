class ProgramGroup < ApplicationRecord
  DEGREE_LEVELS = %w[bachelor master doctoral].freeze

  DEGREE_LEVEL_ICONS = {
    "bachelor" => "school",
    "master"   => "psychology",
    "doctoral" => "science"
  }.freeze

  PLACEHOLDER_NAME = "Unknown Program".freeze

  has_many :programs, dependent: :restrict_with_error
  has_many :students, through: :programs
  has_many :courses, through: :programs
  has_many :staff_programs, through: :programs
  has_many :staffs, -> { distinct }, through: :staff_programs

  validates :code, presence: true, uniqueness: true
  validates :name_en, presence: true
  validates :degree_level, presence: true, inclusion: { in: DEGREE_LEVELS }
  validates :degree_name, presence: true
  validates :field_of_study, presence: true

  def display_name
    "#{name_en} (#{code})"
  end

  def placeholder?
    code == "OTHER"
  end
end
