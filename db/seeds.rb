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
  programs = [
    { name_en: "Computer Engineering",                    name_th: "วิศวกรรมคอมพิวเตอร์",                        degree_level: "bachelor", degree_name: "Bachelor of Engineering",       field_of_study: "Computer Engineering", year_started: 2540 },
    { name_en: "Computer Engineering",                    name_th: "วิศวกรรมคอมพิวเตอร์",                        degree_level: "master",   degree_name: "Master of Engineering",        field_of_study: "Computer Engineering", year_started: 2545 },
    { name_en: "Computer Engineering",                    name_th: "วิศวกรรมคอมพิวเตอร์",                        degree_level: "doctoral", degree_name: "Doctor of Philosophy",         field_of_study: "Computer Engineering", year_started: 2550 },
    { name_en: "Computer Science and Information Science", name_th: "วิทยาศาสตร์คอมพิวเตอร์และเทคโนโลยีสารสนเทศ", degree_level: "bachelor", degree_name: "Bachelor of Science",          field_of_study: "Computer Science",     year_started: 2560 },
  ].map do |attrs|
    Program.find_or_create_by!(name_en: attrs[:name_en], degree_level: attrs[:degree_level]) do |p|
      p.assign_attributes(attrs)
    end
  end

  cp_bachelor = programs[0]

  [
    { student_id: "6732100021", first_name: "Thanawat",  last_name: "Sricharoen",   first_name_th: "ธนวัฒน์",  last_name_th: "ศรีเจริญ",   admission_year: 2567, email: "thanawat.s@student.chula.ac.th",  discord: "thanawat#1234", previous_school: "Triam Udom Suksa", enrollment_method: "Direct Admission", program: cp_bachelor },
    { student_id: "6732100039", first_name: "Siriporn",  last_name: "Jantaraksa",   first_name_th: "ศิริพร",   last_name_th: "จันทรักษา",  admission_year: 2567, email: "siriporn.j@student.chula.ac.th", line_id: "siriporn_j",    previous_school: "Mahidol Wittayanusorn", enrollment_method: "TCAS Round 1", program: cp_bachelor },
    { student_id: "6732100047", first_name: "Natthaphon", last_name: "Kaewmanee",   first_name_th: "ณัฐพล",    last_name_th: "แก้วมณี",    admission_year: 2567, email: "natthaphon.k@student.chula.ac.th", phone: "081-234-5678", guardian_name: "Somchai Kaewmanee", guardian_phone: "089-876-5432", previous_school: "Suankularb Wittayalai", enrollment_method: "TCAS Round 3", program: cp_bachelor },
    { student_id: "6632100055", first_name: "Ploypailin", last_name: "Wongprasert",  first_name_th: "พลอยไพลิน", last_name_th: "วงศ์ประเสริฐ", admission_year: 2566, email: "ploypailin.w@student.chula.ac.th", discord: "ploy_w#5678", previous_school: "Kasetsart University Laboratory School", enrollment_method: "TCAS Round 2", program: cp_bachelor },
    { student_id: "6632100063", first_name: "Kittipat",  last_name: "Thongkham",    first_name_th: "กิตติพัฒน์", last_name_th: "ทองคำ",      admission_year: 2566, status: "on_leave", email: "kittipat.t@student.chula.ac.th", program: cp_bachelor },
    { student_id: "6532100071", first_name: "Arunee",    last_name: "Phanomwan",    first_name_th: "อรุณี",    last_name_th: "พนมวัน",     admission_year: 2565, status: "graduated", email: "arunee.p@student.chula.ac.th", previous_school: "Chulalongkorn University Demonstration School", enrollment_method: "Direct Admission", program: cp_bachelor },
  ].each do |attrs|
    Student.find_or_create_by!(student_id: attrs[:student_id]) do |s|
      s.assign_attributes(attrs.except(:student_id))
    end
  end

  puts "Seed complete. Super admin + 5 dev users + 4 programs + 6 students ready."
else
  puts "Seed complete. Super admin user (ID 1) ready."
end
