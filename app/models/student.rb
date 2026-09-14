class Student < ApplicationRecord
  SEXES = %w[M F].freeze
  STATUSES = %w[active graduated on_leave retired unknown].freeze
  TCAS_ROUNDS = %w[TCAS1 TCAS2 TCAS3 TCAS4 other unknown].freeze

  # Material Symbols icon for each status — used by Select2 dropdowns
  # and anywhere else that needs a visual indicator for status.
  STATUS_ICONS = {
    "active"    => "check_circle",
    "graduated" => "school",
    "on_leave"  => "pause_circle",
    "retired"   => "exit_to_app",
    "unknown"   => "help"
  }.freeze

  # M.Sc. study track: ภาคปกติ vs ภาคนอกเวลาราชการ (the department's "CT"
  # cohorts, CS intakes 2533–2560). Null = unknown or not applicable
  # (bachelors, unclassified eras). Backfilled from registrar evidence —
  # see docs/superpowers/specs/2026-08-21-cs-study-track-design.md.
  # Deliberately has NO importer attribute, so file imports never touch it.
  STUDY_TRACKS = %w[regular special].freeze
  STUDY_TRACK_ICONS = { "regular" => "light_mode", "special" => "dark_mode" }.freeze
  STUDY_TRACK_LABELS = { "regular" => "Regular", "special" => "นอกเวลาราชการ" }.freeze

  # Where a student row came from. `book30` rows are placeholders built from the
  # 30-year anniversary book (Thai names only, synthetic IDs) — see
  # docs/superpowers/specs/2026-09-14-book30-import-design.md. LEGACY_SOURCES are
  # the ones allowed to lack English names.
  SOURCES = %w[imported chulabooster manual book30].freeze
  LEGACY_SOURCES = %w[book30].freeze
  SOURCE_LABELS = {
    "imported"     => "Excel import",
    "chulabooster" => "ChulaBooster",
    "manual"       => "Manual entry",
    "book30"       => "30-year book"
  }.freeze
  SOURCE_ICONS = {
    "imported"     => "upload_file",
    "chulabooster" => "sync",
    "manual"       => "edit",
    "book30"       => "menu_book"
  }.freeze

  belongs_to :program
  has_many :grades, dependent: :destroy
  has_many :advisorships, dependent: :destroy
  has_many :current_advisorships, -> { current }, class_name: "Advisorship", inverse_of: :student
  has_many :advisors, through: :current_advisorships, source: :staff
  has_many :book30_entries, dependent: :nullify

  validates :student_id, presence: true, uniqueness: true
  validates :first_name, presence: true, unless: :legacy_source?
  validates :last_name, presence: true, unless: :legacy_source?
  validates :first_name_th, presence: true
  validates :last_name_th, presence: true
  validates :admission_year_be, presence: true, numericality: { only_integer: true }
  validates :sex, inclusion: { in: SEXES }, allow_nil: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :tcas, inclusion: { in: TCAS_ROUNDS }, allow_nil: true
  validates :study_track, inclusion: { in: STUDY_TRACKS }, allow_nil: true
  validates :source, presence: true, inclusion: { in: SOURCES }

  # Blank select submissions arrive as "" — store the absence as NULL.
  before_validation { self.study_track = nil if study_track.blank? }

  scope :active, -> { where(status: "active") }

  def full_name
    return nil if first_name.blank? && last_name.blank?
    "#{first_name} #{last_name}".strip
  end

  def full_name_th
    return nil if first_name_th.blank? && last_name_th.blank?
    "#{first_name_th} #{last_name_th}"
  end

  # Prefer Thai name for display; fall back to English, then to the ID (book
  # placeholders have no English name at all).
  def display_name
    full_name_th.presence || full_name.presence || student_id
  end

  def legacy_source?
    source.in?(LEGACY_SOURCES)
  end

  def active?
    status == "active"
  end

  def graduated?
    status == "graduated"
  end

  def on_leave?
    status == "on_leave"
  end

  def retired?
    status == "retired"
  end

  def gpa
    graded = grades.joins(:course).where.not(grade_weight: nil)
    total_weighted = graded.sum("grades.grade_weight * courses.credits")
    total_credits = graded.sum("courses.credits")
    total_credits.zero? ? nil : (total_weighted / total_credits).round(2)
  end

  def total_credits
    grades.joins(:course).where.not(grade_weight: nil).sum("courses.credits")
  end
end
