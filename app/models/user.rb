class User < ApplicationRecord
  has_secure_password

  ROLES = %w[admin staff viewer].freeze

  # Material Symbols icon for each role — used by Tom Select dropdowns
  # and anywhere else that needs a visual indicator for role.
  ROLE_ICONS = {
    "admin"  => "shield_person",
    "staff"  => "work",
    "viewer" => "visibility"
  }.freeze

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :uid, uniqueness: { scope: :provider }, allow_nil: true

  scope :active, -> { where(active: true) }

  def admin?
    role == "admin"
  end

  def staff?
    role == "staff"
  end

  def viewer?
    role == "viewer"
  end
end
