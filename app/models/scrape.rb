class Scrape < ApplicationRecord
  SOURCES = %w[cugetreg cas_reg].freeze
  STUDY_PROGRAMS = %w[S T I].freeze
  STATES = %w[pending running completed failed].freeze

  belongs_to :semester
  belongs_to :user

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :study_program, presence: true, inclusion: { in: STUDY_PROGRAMS }
  validates :state, presence: true, inclusion: { in: STATES }

  scope :recent, -> { order(created_at: :desc) }

  def running?
    state == "running"
  end

  def completed?
    state == "completed"
  end

  def failed?
    state == "failed"
  end

  def source_label
    case source
    when "cugetreg" then "CuGetReg"
    when "cas_reg" then "CAS Reg Chula"
    end
  end
end
