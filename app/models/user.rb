class User < ApplicationRecord
  has_secure_password

  ROLES = %w[admin editor viewer].freeze

  # Material Symbols icon for each role — used by Select2 dropdowns
  # and anywhere else that needs a visual indicator for role.
  ROLE_ICONS = {
    "admin"  => "shield_person",
    "editor" => "edit",
    "viewer" => "visibility"
  }.freeze

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :uid, uniqueness: { scope: :provider }, allow_nil: true
  validates :llm_model, inclusion: { in: LLM_CONFIG[:models].keys.map(&:to_s) }, allow_nil: true

  scope :active, -> { where(active: true) }

  def admin?
    role == "admin"
  end

  def editor?
    role == "editor"
  end

  def viewer?
    role == "viewer"
  end
end
