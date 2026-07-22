class MoveUsersToRoleRecords < ActiveRecord::Migration[8.1]
  # Table-only stand-ins: migrations must not depend on app models.
  class MigRole < ActiveRecord::Base
    self.table_name = "roles"
  end

  # The four seed roles are created HERE (not only in db/seeds.rb) because the
  # role_id backfill needs them, and existing DBs migrate rather than reseed.
  # db/seeds.rb repeats them idempotently for fresh schema-loaded installs.
  ROLE_ROWS = {
    "public_info" => { description: "Public-by-nature data - course offerings and basic course info",
                       permission_keys: ["courses.read"], locked: false },
    "minimal"     => { description: "Minimal student access - identity, program, admission year",
                       permission_keys: ["students.read_minimal"], locked: false },
    "staff"       => { description: "Department staff - full read access, advisee access via advisorships",
                       permission_keys: ["students.read_full", "grades.read", "advisees.read_full"], locked: false },
    "admin"       => { description: "Administrator - everything",
                       permission_keys: ["courses.read", "students.read_minimal", "students.read_full",
                                         "grades.read", "advisees.read_full", "users.manage"], locked: true }
  }.freeze

  def up
    add_reference :users, :role, foreign_key: true

    ids = {}
    ROLE_ROWS.each do |name, attrs|
      row = MigRole.find_or_create_by!(name: name) { |r| r.assign_attributes(attrs) }
      ids[name] = row.id
    end
    [%w[minimal public_info], %w[staff minimal]].each do |child, parent|
      execute <<~SQL.squish
        INSERT INTO role_inheritances (role_id, parent_role_id, created_at, updated_at)
        SELECT #{ids[child]}, #{ids[parent]}, NOW(), NOW()
        WHERE NOT EXISTS (SELECT 1 FROM role_inheritances
                          WHERE role_id = #{ids[child]} AND parent_role_id = #{ids[parent]})
      SQL
    end

    execute "UPDATE users SET role_id = #{ids['admin']} WHERE role = 'admin'"
    # editor was never actually checked anywhere; both tiers are department
    # insiders and keep their current read-everything access as staff.
    execute "UPDATE users SET role_id = #{ids['staff']} WHERE role IN ('editor', 'viewer')"

    change_column_null :users, :role_id, false
    remove_column :users, :role
  end

  def down
    add_column :users, :role, :string, null: false, default: "viewer"
    execute <<~SQL.squish
      UPDATE users u JOIN roles r ON r.id = u.role_id
      SET u.role = CASE r.name WHEN 'admin' THEN 'admin' ELSE 'viewer' END
    SQL
    remove_reference :users, :role
  end
end
