# One advisor↔advisee assignment. History-preserving: reassignment sets
# ended_on and adds a new row; ended rows grant no access. Overlapping
# active rows are legal (grad co-advisors), but the same (student, staff)
# pair may be active only once.
class Advisorship < ApplicationRecord
  belongs_to :student
  belongs_to :staff

  validates :started_on, presence: true
  validates :student_id, uniqueness: { scope: :staff_id,
                                       conditions: -> { where(ended_on: nil) },
                                       message: "already has this staff member as a current advisor" }
  validate :ended_after_started

  scope :current, -> { where(ended_on: nil) }

  def current? = ended_on.nil?

  private

  def ended_after_started
    return if ended_on.blank? || started_on.blank?
    errors.add(:ended_on, "must be on or after the start date") if ended_on < started_on
  end
end
