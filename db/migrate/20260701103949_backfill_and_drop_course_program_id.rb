class BackfillAndDropCourseProgramId < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO program_courses (program_id, course_id, created_at, updated_at)
      SELECT program_id, id, NOW(), NOW() FROM courses
    SQL

    pc = select_value("SELECT COUNT(*) FROM program_courses").to_i
    c  = select_value("SELECT COUNT(*) FROM courses").to_i
    raise "backfill count mismatch (#{pc} != #{c}) — aborting" unless pc == c

    remove_foreign_key :courses, :programs   # MySQL: FK must go before the column
    remove_column :courses, :program_id      # also drops index_courses_on_program_id
  end

  def down
    add_column :courses, :program_id, :bigint
    execute <<~SQL
      UPDATE courses c
      JOIN program_courses pc ON pc.course_id = c.id
      SET c.program_id = pc.program_id
    SQL
    change_column_null :courses, :program_id, false
    add_index :courses, :program_id, name: "index_courses_on_program_id"
    add_foreign_key :courses, :programs
    execute "DELETE FROM program_courses"
  end
end
