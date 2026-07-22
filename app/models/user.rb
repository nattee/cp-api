class User < ApplicationRecord
  has_secure_password

  belongs_to :role

  # Least-privilege default: new accounts (manual creation and the LINE
  # quick-link flow alike) start as public_info until an admin raises them.
  before_validation on: :create do
    self.role ||= Role.find_by(name: "public_info")
  end

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :uid, uniqueness: { scope: :provider }, allow_nil: true
  # The form's "Default" option submits "" — normalize to nil so the
  # allow_nil inclusion below treats "no preference" consistently.
  normalizes :llm_model, with: ->(model) { model.presence }
  validates :llm_model, inclusion: { in: LLM_CONFIG[:models].keys.map(&:to_s) }, allow_nil: true

  scope :active, -> { where(active: true) }

  # Effective permission check — the single entry point for authorization.
  # Memoized per instance; role edits take effect on the next request.
  def can?(key)
    permission_set.include?(key)
  end

  def admin?
    can?("users.manage")
  end

  private

  def permission_set
    @permission_set ||= role&.effective_permission_keys || Set.new
  end
end
