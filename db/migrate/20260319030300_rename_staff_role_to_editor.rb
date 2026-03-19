class RenameStaffRoleToEditor < ActiveRecord::Migration[8.0]
  def up
    User.where(role: "staff").update_all(role: "editor")
  end

  def down
    User.where(role: "editor").update_all(role: "staff")
  end
end
