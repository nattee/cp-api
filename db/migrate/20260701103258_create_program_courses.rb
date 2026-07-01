class CreateProgramCourses < ActiveRecord::Migration[8.1]
  def change
    create_table :program_courses do |t|
      t.references :program, null: false, foreign_key: true
      t.references :course,  null: false, foreign_key: true
      t.string  :course_group_code   # nullable — populated later by ChulaBooster sync
      t.integer :course_type         # nullable — populated later by ChulaBooster sync
      t.string  :remark              # nullable — local annotation, sync never overwrites
      t.timestamps
    end
    add_index :program_courses, [:program_id, :course_id], unique: true
  end
end
