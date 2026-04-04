# Placeholder program — used by grade importer when a course has no matching program.
# find_or_create ensures this is idempotent and always available.
Program.placeholder

# Super admin user (ID 1)
User.find_or_create_by!(id: 1) do |u|
  u.username = "root"
  u.email = "nattee@cp.eng.chula.ac.th"
  u.name = "dae (superadmin)"
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = "admin"
end

# Load additional seed files
Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| load f }

puts "Seed complete. Super admin user (ID 1) ready."
