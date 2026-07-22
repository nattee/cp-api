# Roles must exist before any user row — users.role_id is NOT NULL. The same
# four roles are created by the MoveUsersToRoleRecords migration on migrated
# DBs; a fresh install loads schema.rb (no migration data), so seeds repeat
# them idempotently here.
{
  "public_info" => { description: "Public-by-nature data - course offerings and basic course info",
                     permission_keys: ["courses.read"], locked: false, parents: [] },
  "minimal"     => { description: "Minimal student access - identity, program, admission year",
                     permission_keys: ["students.read_minimal"], locked: false, parents: ["public_info"] },
  "staff"       => { description: "Department staff - full read access, advisee access via advisorships",
                     permission_keys: ["students.read_full", "grades.read", "advisees.read_full"],
                     locked: false, parents: ["minimal"] },
  "admin"       => { description: "Administrator - everything",
                     permission_keys: Permission::KEYS.dup, locked: true, parents: [] }
}.each do |name, attrs|
  role = Role.find_or_create_by!(name: name) do |r|
    r.description = attrs[:description]
    r.permission_keys = attrs[:permission_keys]
    r.locked = attrs[:locked]
  end
  attrs[:parents].each do |parent_name|
    parent = Role.find_by!(name: parent_name)
    RoleInheritance.find_or_create_by!(role: role, parent_role: parent)
  end
end

# Super admin user (ID 1)
User.find_or_create_by!(id: 1) do |u|
  u.username = "root"
  u.email = "nattee@cp.eng.chula.ac.th"
  u.name = "dae (superadmin)"
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = Role.find_by!(name: "admin")
end

# Load additional seed files (creates ProgramGroups, Programs, Staff)
Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| load f }

# Placeholder program — needs ProgramGroup "OTHER" from seeds/programs.rb
Program.placeholder

puts "Seed complete. Super admin user (ID 1) ready."
