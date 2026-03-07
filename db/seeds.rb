# Super admin user (ID 1)
User.find_or_create_by!(id: 1) do |u|
  u.username = "superadmin"
  u.email = "superadmin@cp.eng.chula.ac.th"
  u.name = "Super Admin"
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = "admin"
end

if Rails.env.development?
  [
    { username: "somchai.w",  email: "somchai.w@cp.eng.chula.ac.th",  name: "Somchai Wongsakul",  role: "staff" },
    { username: "naree.k",    email: "naree.k@cp.eng.chula.ac.th",    name: "Naree Kittisak",     role: "viewer" },
    { username: "pichit.s",   email: "pichit.s@cp.eng.chula.ac.th",   name: "Pichit Srisombat",   role: "staff" },
    { username: "anucha.p",   email: "anucha.p@cp.eng.chula.ac.th",   name: "Anucha Prasert",     role: "admin" },
    { username: "kannika.t",  email: "kannika.t@cp.eng.chula.ac.th",  name: "Kannika Thongchai",  role: "viewer", active: false },
  ].each do |attrs|
    User.find_or_create_by!(username: attrs[:username]) do |u|
      u.email = attrs[:email]
      u.name = attrs[:name]
      u.password = "password123"
      u.password_confirmation = "password123"
      u.role = attrs[:role]
      u.active = attrs.fetch(:active, true)
    end
  end
  puts "Seed complete. Super admin + 5 dev users ready."
else
  puts "Seed complete. Super admin user (ID 1) ready."
end
