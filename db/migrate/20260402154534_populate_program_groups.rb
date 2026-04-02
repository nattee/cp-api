class PopulateProgramGroups < ActiveRecord::Migration[8.1]
  def up
    groups = [
      { code: "CP",    name_en: "Computer Engineering",                          name_th: "วิศวกรรมคอมพิวเตอร์",                               degree_level: "bachelor", degree_name: "Bachelor of Engineering",  degree_name_th: "วิศวกรรมศาสตรบัณฑิต",        field_of_study: "Computer Engineering" },
      { code: "CEDT",  name_en: "Computer Engineering and Digital Technology",   name_th: "วิศวกรรมคอมพิวเตอร์และเทคโนโลยีดิจิทัล",            degree_level: "bachelor", degree_name: "Bachelor of Engineering",  degree_name_th: "วิศวกรรมศาสตรบัณฑิต",        field_of_study: "Computer Engineering" },
      { code: "CM",    name_en: "Computer Engineering",                          name_th: "วิศวกรรมคอมพิวเตอร์",                               degree_level: "master",   degree_name: "Master of Engineering",   degree_name_th: "วิศวกรรมศาสตรมหาบัณฑิต",     field_of_study: "Computer Engineering" },
      { code: "CS",    name_en: "Computer Science",                              name_th: "วิทยาศาสตร์คอมพิวเตอร์",                            degree_level: "master",   degree_name: "Master of Science",       degree_name_th: "วิทยาศาสตรมหาบัณฑิต",        field_of_study: "Computer Engineering" },
      { code: "SE",    name_en: "Software Engineering",                          name_th: "วิศวกรรมซอฟต์แวร์",                                 degree_level: "master",   degree_name: "Master of Science",       degree_name_th: "วิทยาศาสตรมหาบัณฑิต",        field_of_study: "Computer Engineering" },
      { code: "CD",    name_en: "Computer Engineering",                          name_th: "วิศวกรรมคอมพิวเตอร์",                               degree_level: "doctoral", degree_name: "Doctor of Philosophy",    degree_name_th: "วิศวกรรมศาสตรดุษฎีบัณฑิต",   field_of_study: "Computer Engineering" },
      { code: "OTHER", name_en: "Unknown Program",                               name_th: nil,                                                  degree_level: "bachelor", degree_name: "Unknown",                degree_name_th: nil,                           field_of_study: "Unknown" },
    ]

    now = Time.zone.now.utc.strftime("%Y-%m-%d %H:%M:%S")

    groups.each do |g|
      execute <<~SQL.squish
        INSERT INTO program_groups (code, name_en, name_th, degree_level, degree_name, degree_name_th, field_of_study, created_at, updated_at)
        VALUES (#{quote(g[:code])}, #{quote(g[:name_en])}, #{quote(g[:name_th])}, #{quote(g[:degree_level])}, #{quote(g[:degree_name])}, #{quote(g[:degree_name_th])}, #{quote(g[:field_of_study])}, '#{now}', '#{now}')
      SQL
    end

    # Assign programs to groups using deterministic rules (order matters)
    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'CEDT')
      WHERE name_en LIKE '%Digital Technology%'
    SQL

    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'CD')
      WHERE degree_level = 'doctoral' AND program_group_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'SE')
      WHERE degree_level = 'master' AND degree_name = 'Master of Science'
        AND name_en = 'Software Engineering' AND program_group_id IS NULL
    SQL

    # CS: remaining Master of Science (catches code 0999 which has name_en "Computer Engineering" but is CS)
    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'CS')
      WHERE degree_level = 'master' AND degree_name = 'Master of Science'
        AND program_group_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'CM')
      WHERE degree_level = 'master' AND degree_name = 'Master of Engineering'
        AND program_group_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'CP')
      WHERE degree_level = 'bachelor' AND program_group_id IS NULL
        AND program_code != '0000'
    SQL

    # Catch-all: placeholder and any unmatched programs
    execute <<~SQL.squish
      UPDATE programs SET program_group_id = (SELECT id FROM program_groups WHERE code = 'OTHER')
      WHERE program_group_id IS NULL
    SQL
  end

  def down
    execute "UPDATE programs SET program_group_id = NULL"
    execute "DELETE FROM program_groups"
  end

  private

  def quote(value)
    value.nil? ? "NULL" : ActiveRecord::Base.connection.quote(value)
  end
end
