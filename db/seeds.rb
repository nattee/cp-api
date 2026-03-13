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

  [
    { course_no: "2110101", revision_year: 2565, name: "Computer Programming",                    name_th: "การเขียนโปรแกรมคอมพิวเตอร์",          name_abbr: "COMP PROG",    course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 2, nl_hours: 2, s_hours: 5, program: cp_bachelor },
    { course_no: "2110201", revision_year: 2565, name: "Computer Engineering Essentials",          name_th: "สาระสำคัญของวิศวกรรมคอมพิวเตอร์",     name_abbr: "CE ESSEN",     course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110211", revision_year: 2565, name: "Data Structures",                         name_th: "โครงสร้างข้อมูล",                     name_abbr: "DATA STRUCT",  course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 2, nl_hours: 2, s_hours: 5, program: cp_bachelor },
    { course_no: "2110215", revision_year: 2565, name: "Programming Methodology",                 name_th: "ระเบียบวิธีการเขียนโปรแกรม",           name_abbr: "PROG METHOD",  course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 2, nl_hours: 2, s_hours: 5, program: cp_bachelor },
    { course_no: "2110263", revision_year: 2565, name: "Digital Logic Lab",                        name_th: "ปฏิบัติการตรรกะดิจิทัล",                name_abbr: "DIGI LAB",     course_group: "Core",    department_code: "21", credits: 1, l_credits: 0, nl_credits: 1, l_hours: 0, nl_hours: 3, s_hours: 0, program: cp_bachelor },
    { course_no: "2110313", revision_year: 2565, name: "Operating Systems",                       name_th: "ระบบปฏิบัติการ",                       name_abbr: "OS",           course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110327", revision_year: 2565, name: "Algorithm Design",                        name_th: "การออกแบบขั้นตอนวิธี",                 name_abbr: "ALGO",         course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110332", revision_year: 2565, name: "Systems Programming",                     name_th: "การเขียนโปรแกรมระบบ",                  name_abbr: "SYS PROG",     course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 2, nl_hours: 2, s_hours: 5, program: cp_bachelor },
    { course_no: "2110363", revision_year: 2565, name: "Computer Architecture",                   name_th: "สถาปัตยกรรมคอมพิวเตอร์",               name_abbr: "COMP ARCH",    course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110422", revision_year: 2565, name: "Database Systems",                        name_th: "ระบบฐานข้อมูล",                        name_abbr: "DB SYS",       course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110443", revision_year: 2565, name: "Software Engineering",                    name_th: "วิศวกรรมซอฟต์แวร์",                    name_abbr: "SW ENG",       course_group: "Core",    department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, program: cp_bachelor },
    { course_no: "2110499", revision_year: 2565, name: "Senior Project",                          name_th: "โครงงานวิศวกรรมคอมพิวเตอร์",           name_abbr: "SR PROJ",      course_group: "Project", department_code: "21", credits: 3, l_credits: 0, nl_credits: 3, l_hours: 0, nl_hours: 9, s_hours: 0, program: cp_bachelor },
    { course_no: "2103106", revision_year: 2560, name: "General Physics",                         name_th: "ฟิสิกส์ทั่วไป",                        name_abbr: "GEN PHYS",     course_group: "GenEd",   department_code: "21", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, is_gened: true, program: cp_bachelor },
    { course_no: "2301108", revision_year: 2560, name: "Calculus I",                              name_th: "แคลคูลัส 1",                           name_abbr: "CALC I",       course_group: "GenEd",   department_code: "23", credits: 3, l_credits: 3, nl_credits: 0, l_hours: 3, nl_hours: 0, s_hours: 6, is_gened: true, program: cp_bachelor },
  ].each do |attrs|
    Course.find_or_create_by!(course_no: attrs[:course_no], revision_year: attrs[:revision_year]) do |c|
      c.assign_attributes(attrs.except(:course_no, :revision_year))
    end
  end

  puts "Seed complete. Super admin + 5 dev users + 4 programs + 6 students + 14 courses ready."
else
  puts "Seed complete. Super admin user (ID 1) ready."
end
