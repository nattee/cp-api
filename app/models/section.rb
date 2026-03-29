class Section < ApplicationRecord
  belongs_to :course_offering
  has_many :time_slots, dependent: :destroy
  has_many :teachings, dependent: :destroy

  accepts_nested_attributes_for :time_slots, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :teachings, allow_destroy: true, reject_if: :all_blank

  validates :section_number, presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :section_number, uniqueness: { scope: :course_offering_id }
end
