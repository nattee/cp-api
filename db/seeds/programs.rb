# Seed data for Program Groups and Programs
# year_started values are in Buddhist Era (B.E.)

# --- Program Groups ---
group_data = {
  "CP"    => { name_en: "Computer Engineering",                        name_th: "วิศวกรรมคอมพิวเตอร์",                            degree_level: "bachelor", degree_name: "Bachelor of Engineering",  degree_name_th: "วิศวกรรมศาสตรบัณฑิต",      field_of_study: "Computer Engineering" },
  "CEDT"  => { name_en: "Computer Engineering and Digital Technology", name_th: "วิศวกรรมคอมพิวเตอร์และเทคโนโลยีดิจิทัล",         degree_level: "bachelor", degree_name: "Bachelor of Engineering",  degree_name_th: "วิศวกรรมศาสตรบัณฑิต",      field_of_study: "Computer Engineering" },
  "CM"    => { name_en: "Computer Engineering",                        name_th: "วิศวกรรมคอมพิวเตอร์",                            degree_level: "master",   degree_name: "Master of Engineering",   degree_name_th: "วิศวกรรมศาสตรมหาบัณฑิต",   field_of_study: "Computer Engineering" },
  "CS"    => { name_en: "Computer Science",                            name_th: "วิทยาศาสตร์คอมพิวเตอร์",                         degree_level: "master",   degree_name: "Master of Science",       degree_name_th: "วิทยาศาสตรมหาบัณฑิต",      field_of_study: "Computer Engineering" },
  "SE"    => { name_en: "Software Engineering",                        name_th: "วิศวกรรมซอฟต์แวร์",                              degree_level: "master",   degree_name: "Master of Science",       degree_name_th: "วิทยาศาสตรมหาบัณฑิต",      field_of_study: "Computer Engineering" },
  "CD"    => { name_en: "Computer Engineering",                        name_th: "วิศวกรรมคอมพิวเตอร์",                            degree_level: "doctoral", degree_name: "Doctor of Philosophy",    degree_name_th: "วิศวกรรมศาสตรดุษฎีบัณฑิต", field_of_study: "Computer Engineering" },
  "OTHER" => { name_en: "Unknown Program",                             name_th: nil,                                               degree_level: "bachelor", degree_name: "Unknown",                degree_name_th: nil,                         field_of_study: "Unknown" },
}

groups = {}
group_data.each do |code, attrs|
  group = ProgramGroup.find_or_initialize_by(code: code)
  group.update!(attrs)
  groups[code] = group
end

# --- Programs (revisions) ---
# Each program only declares revision-specific fields.
programs = {
  "CD" => [
    { program_code: "0458", total_credit: 72, short_name: "วศ.ด.",      year_started: 1998 + 543 },
    { program_code: "0459", total_credit: 60, short_name: "วศ.ด.",      year_started: 1998 + 543 },
    { program_code: "2696", total_credit: 60, short_name: "วศ.ด.",      year_started: 2015 + 543 },
    { program_code: "2697", total_credit: 72, short_name: "วศ.ด. (CD)", year_started: 2015 + 543 },
    { program_code: "3482", total_credit: 60, short_name: "วศ.ด. (CD)", year_started: 2018 + 543 },
    { program_code: "3483", total_credit: 72, short_name: "วศ.ด. (CD)", year_started: 2018 + 543 },
    { program_code: "3484", total_credit: 60, short_name: "วศ.ด. (CD)", year_started: 2018 + 543 },
    { program_code: "3485", total_credit: 72, short_name: "วศ.ด. (CD)", year_started: 2018 + 543 },
    { program_code: "4236", total_credit: 60, short_name: "วศ.ด. (CD)", year_started: 2023 + 543 },
    { program_code: "4237", total_credit: 72, short_name: "วศ.ด. (CD)", year_started: 2023 + 543 },
    { program_code: "4238", total_credit: 60, short_name: "วศ.ด. (CD)", year_started: 2023 + 543 },
    { program_code: "4239", total_credit: 72, short_name: "วศ.ด. (CD)", year_started: 2023 + 543 },
  ],
  "SE" => [
    { program_code: "0772", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2002 + 543 },
    { program_code: "0773", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2002 + 543 },
    { program_code: "2628", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2015 + 543 },
    { program_code: "2629", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2015 + 543 },
    { program_code: "3338", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2018 + 543 },
    { program_code: "3339", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2018 + 543 },
    { program_code: "4240", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2023 + 543 },
    { program_code: "4241", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2023 + 543 },
    { program_code: "5119", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2026 + 543 },
    { program_code: "5120", total_credit: 36, short_name: "วท.ม. (SE)", year_started: 2026 + 543 },
  ],
  "CS" => [
    { program_code: "0038", total_credit: 36, short_name: "วท.ม. (CS)", year_started: 1995 + 543 },
    { program_code: "1027", total_credit: 48, short_name: "วท.ม. (CS)", year_started: 1981 + 543 },
    { program_code: "2205", total_credit: 36, short_name: "วท.ม. (CS)", year_started: 2014 + 543 },
    { program_code: "3626", total_credit: 36, short_name: "วท.ม. (CS)", year_started: 2018 + 543 },
    { program_code: "4242", total_credit: 36, short_name: "วท.ม. (CS)", year_started: 2023 + 543 },
    # Strange one: CS but has CM-like name_en — group assignment is by seed structure, not by name
    { program_code: "0999", total_credit: 48, short_name: "วท.ม. (CS)", year_started: 1997 + 543 },
  ],
  "CM" => [
    { program_code: "0037", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 1992 + 543 },
    { program_code: "0938", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2003 + 543 },
    { program_code: "2694", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2015 + 543 },
    { program_code: "2695", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2015 + 543 },
    { program_code: "3336", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2018 + 543 },
    { program_code: "3337", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2018 + 543 },
    { program_code: "4234", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2023 + 543 },
    { program_code: "4235", total_credit: 36, short_name: "วศ.ม. (CM)", year_started: 2023 + 543 },
  ],
  "CP" => [
    { program_code: "0018", total_credit: 141, short_name: "วศ.บ. (CP)", year_started: 1976 + 543 },
    { program_code: "0570", total_credit: 143, short_name: "วศ.บ. (CP)", year_started: 1996 + 543 },
    { program_code: "0779", total_credit: 145, short_name: "วศ.บ. (CP)", year_started: 2002 + 543 },
    { program_code: "0928", total_credit: 141, short_name: "วศ.บ. (CP)", year_started: 1996 + 543 },
    { program_code: "1933", total_credit: 142, short_name: "วศ.บ. (CP)", year_started: 2554 },
    { program_code: "2909", total_credit: 145, short_name: "วศ.บ. (CP)", year_started: 2559 },
    { program_code: "3736", total_credit: 141, short_name: "วศ.บ. (CP)", year_started: 2561 },
    { program_code: "4784", total_credit: 138, short_name: "วศ.บ. (CP)", year_started: 2566 },
  ],
  "CEDT" => [
    { program_code: "4853", total_credit: 124, short_name: "วศ.บ. (CEDT)", year_started: 2566 },
  ],
}

programs.each do |group_code, revisions|
  group = groups[group_code]
  revisions.each do |attrs|
    attrs[:active] = attrs[:year_started] > 2560
    attrs[:program_group] = group

    program = Program.find_or_initialize_by(program_code: attrs[:program_code])
    program.update!(attrs)
  end
end
