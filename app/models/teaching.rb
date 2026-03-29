class Teaching < ApplicationRecord
  belongs_to :section
  belongs_to :staff

  validates :load_ratio, presence: true,
    numericality: { greater_than: 0, less_than_or_equal_to: 1 }
  validates :staff_id, uniqueness: { scope: :section_id }
end
