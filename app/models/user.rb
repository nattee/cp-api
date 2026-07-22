class User < ApplicationRecord
  has_secure_password

  belongs_to :role
  belongs_to :staff, optional: true

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

  # Current advisee student IDs via the linked Staff record; empty when the
  # account has no staff link. Memoized per request.
  def advisee_ids
    @advisee_ids ||= staff ? staff.current_advisorships.pluck(:student_id) : []
  end

  def advisee?(student)
    advisee_ids.include?(student.id)
  end

  # Composite scoped checks — single source of truth; views and LINE tools
  # must use these, never re-derive the advisee logic.
  def can_view_student_fully?(student)
    can?("students.read_full") || (can?("advisees.read_full") && advisee?(student))
  end

  def can_view_grades?(student)
    can?("grades.read") || (can?("advisees.read_full") && advisee?(student))
  end

  private

  def permission_set
    @permission_set ||= role&.effective_permission_keys || Set.new
  end
end
