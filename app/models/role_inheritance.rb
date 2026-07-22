# One DAG edge: `role` inherits everything `parent_role` grants. Cycles are
# rejected here (an edge role→parent is a cycle iff role is already an
# ancestor of parent).
class RoleInheritance < ApplicationRecord
  belongs_to :role, inverse_of: :role_inheritances
  belongs_to :parent_role, class_name: "Role", inverse_of: :child_inheritances

  validates :parent_role_id, uniqueness: { scope: :role_id }
  validate :not_self
  validate :no_cycle
  validate :child_not_locked

  private

  def not_self
    errors.add(:parent_role, "cannot be the role itself") if role_id.present? && role_id == parent_role_id
  end

  def no_cycle
    return if role.nil? || parent_role.nil? || role_id == parent_role_id
    if parent_role.id == role.id || parent_role.ancestor_role_ids.include?(role.id)
      errors.add(:parent_role, "would create an inheritance cycle")
    end
  end

  def child_not_locked
    errors.add(:base, "Locked roles cannot change inheritance.") if role&.locked?
  end
end
