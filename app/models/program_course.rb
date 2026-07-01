class ProgramCourse < ApplicationRecord
  belongs_to :program
  belongs_to :course

  validates :course_id, uniqueness: { scope: :program_id }
end
