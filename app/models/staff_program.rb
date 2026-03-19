class StaffProgram < ApplicationRecord
  ROLES = %w[head secretary member].freeze

  ROLE_ICONS = {
    "head"      => "star",
    "secretary" => "edit_note",
    "member"    => "group"
  }.freeze

  belongs_to :staff
  belongs_to :program

  validates :role, inclusion: { in: ROLES }, allow_nil: true
end
