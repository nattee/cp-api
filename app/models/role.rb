# A named bundle of permissions, editable by admins at /roles. Roles form a
# DAG via role_inheritances: effective permissions are the role's own
# permission_keys plus everything from its ancestors. Keys must come from
# Permission::CATALOG — the catalog is code, the bundling is data.
class Role < ApplicationRecord
  has_many :users, dependent: :restrict_with_error

  has_many :role_inheritances, dependent: :destroy, inverse_of: :role
  has_many :parent_roles, through: :role_inheritances
  has_many :child_inheritances, class_name: "RoleInheritance",
           foreign_key: :parent_role_id, dependent: :restrict_with_error,
           inverse_of: :parent_role
  has_many :child_roles, through: :child_inheritances, source: :role

  validates :name, presence: true, uniqueness: true
  validate :permission_keys_in_catalog
  validate :locked_role_immutable, on: :update

  before_destroy :prevent_locked_destroy

  def permission_keys
    super || []
  end

  def display_name
    name.titleize
  end

  # Own keys ∪ all ancestors' keys. BFS with a visited set: edges are
  # cycle-validated on write, but a stale cycle must never hang a request.
  def effective_permission_keys
    keys = Set.new
    visited = Set.new
    queue = [self]
    while (role = queue.shift)
      next if role.id && visited.include?(role.id)
      visited << role.id if role.id
      keys.merge(role.permission_keys)
      queue.concat(role.parent_roles.to_a)
    end
    keys
  end

  def ancestor_role_ids
    ids = []
    visited = Set.new
    queue = parent_roles.to_a
    while (role = queue.shift)
      next if visited.include?(role.id)
      visited << role.id
      ids << role.id
      queue.concat(role.parent_roles.to_a)
    end
    ids
  end

  private

  def permission_keys_in_catalog
    invalid = permission_keys.reject { |k| Permission.valid_key?(k) }
    errors.add(:permission_keys, "contains unknown keys: #{invalid.join(', ')}") if invalid.any?
  end

  # The seeded admin role is locked so an admin cannot lock themselves out by
  # unchecking users.manage on their own role.
  def locked_role_immutable
    errors.add(:base, "This role is locked and cannot be modified.") if locked? && changed?
  end

  def prevent_locked_destroy
    if locked?
      errors.add(:base, "This role is locked and cannot be deleted.")
      throw :abort
    end
  end
end
