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
  has_many :program_courses, through: :programs
  has_many :courses, -> { distinct }, through: :program_courses
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

  # Compact picker/label form ("CP — B.Eng."); code alone when no abbr (OTHER).
  def short_label
    degree_abbr.present? ? "#{code} — #{degree_abbr}" : code
  end

  def placeholder?
    code == "OTHER"
  end

  # Cohort/generation notation: "CP53" = the 53rd CP intake. Generations are
  # anchored by first_intake_year_be (institutional knowledge, seeds-managed):
  # generation 1 enrolled in first_intake_year_be.
  def year_for_generation(generation)
    return nil if first_intake_year_be.blank? || generation.to_i < 1
    first_intake_year_be + generation.to_i - 1
  end

  def generation_for_year(year_be)
    return nil if first_intake_year_be.blank? || year_be.blank?
    gen = year_be.to_i - first_intake_year_be + 1
    gen >= 1 ? gen : nil
  end

  # "CP53"-style label for a cohort, or nil when the group has no epoch or
  # the year predates it. Unpadded: CEDT generation 1 => "CEDT1".
  def cohort_label(year_be)
    generation = generation_for_year(year_be)
    generation && "#{code}#{generation}"
  end
end
