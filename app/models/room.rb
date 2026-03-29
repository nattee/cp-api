class Room < ApplicationRecord
  ROOM_TYPES = %w[lecture lab seminar other].freeze
  ROOM_TYPE_ICONS = {
    "lecture" => "class",
    "lab"     => "computer",
    "seminar" => "groups",
    "other"   => "room"
  }.freeze

  has_many :time_slots, dependent: :restrict_with_error

  validates :building, presence: true
  validates :room_number, presence: true, uniqueness: { scope: :building }
  validates :room_type, inclusion: { in: ROOM_TYPES }, allow_nil: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def display_name
    "#{building}-#{room_number}"
  end
end
