class DataImport < ApplicationRecord
  STATES = %w[pending retrying processing completed failed].freeze
  MODES = %w[create_only upsert].freeze

  STATE_ICONS = {
    "pending"    => "schedule",
    "retrying"   => "replay",
    "processing" => "sync",
    "completed"  => "check_circle",
    "failed"     => "error"
  }.freeze

  MODE_ICONS = {
    "create_only" => "add_circle",
    "upsert"      => "sync_alt"
  }.freeze

  MODE_LABELS = {
    "create_only" => "Create only",
    "upsert"      => "Create or Update"
  }.freeze

  IMPORTERS = {
    "Student"    => "Importers::StudentImporter",
    "Course"     => "Importers::CourseImporter",
    "Grade"      => "Importers::GradeImporter",
    "Schedule"   => "Importers::ScheduleImporter"
  }.freeze

  TARGETS = IMPORTERS.keys.freeze

  belongs_to :user
  has_one_attached :file

  validates :target_type, presence: true, inclusion: { in: TARGETS }
  validates :mode, presence: true, inclusion: { in: MODES }
  validates :state, presence: true, inclusion: { in: STATES }
  validates :file, presence: true, on: :create

  def importer_class
    IMPORTERS.fetch(target_type).constantize
  end

  def ready_for_mapping?
    state.in?(%w[pending retrying]) && file.attached?
  end
end
