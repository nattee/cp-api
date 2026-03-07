class User < ApplicationRecord
  has_secure_password

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: %w[admin staff viewer] }
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
