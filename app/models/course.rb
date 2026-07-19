class Course < ApplicationRecord
  has_many :program_courses, dependent: :destroy
  has_many :programs, through: :program_courses
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error

  # Transient: the CourseImporter sets this so a resolved program is linked
  # (additively) after the row is saved. Not a DB column.
  attr_accessor :import_program

  after_save :link_import_program, if: -> { import_program.present? }

  # The Computer Engineering department's course_no prefix. Used by the shared
  # course-list filter (client-side) and available server-side for the pages
  # that still scope with a raw LIKE. Single source of truth for "2110".
  DEPARTMENT_PREFIX = "2110".freeze
  scope :department, -> { where("course_no LIKE ?", "#{DEPARTMENT_PREFIX}%") }

  AUTO_GENERATED_LEVELS = %w[none copied placeholder].freeze

  AUTO_GENERATED_ICONS = {
    "none"        => nil,
    "copied"      => "content_copy",
    "placeholder" => "help_outline"
  }.freeze

  validates :name, presence: true
  validates :course_no, presence: true
  validates :revision_year_be, presence: true, numericality: { only_integer: true }
  validates :course_no, uniqueness: { scope: :revision_year_be, message: "already exists for this revision year" }
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

  private

  def link_import_program
    ProgramCourse.find_or_create_by!(program: import_program, course: self)
  end
end
