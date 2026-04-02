class Program < ApplicationRecord
  # Constants kept here for backward compatibility; canonical source is ProgramGroup
  DEGREE_LEVELS = ProgramGroup::DEGREE_LEVELS
  DEGREE_LEVEL_ICONS = ProgramGroup::DEGREE_LEVEL_ICONS

  PLACEHOLDER_NAME = "Unknown Program".freeze

  belongs_to :program_group
  has_many :courses, dependent: :restrict_with_error
  has_many :students, dependent: :restrict_with_error
  has_many :staff_programs, dependent: :destroy
  has_many :staffs, through: :staff_programs

  # Delegate removed columns to program_group so program.name_en etc. still work
  delegate :name_en, :name_th, :degree_level, :degree_name, :degree_name_th,
           :field_of_study, to: :program_group

  validates :program_code, presence: true, uniqueness: true
  validates :year_started, presence: true, numericality: { only_integer: true }
  validates :total_credit, numericality: { only_integer: true }, allow_nil: true

  def self.placeholder
    other_group = ProgramGroup.find_by!(code: "OTHER")
    find_or_create_by!(program_code: "0000") do |p|
      p.program_group = other_group
      p.year_started = 0
    end
  end

  def placeholder?
    program_code == "0000"
  end
end
