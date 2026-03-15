class CreateEnrollments < ActiveRecord::Migration[8.1]
  def change
    create_table :enrollments do |t|
      t.references :student, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :semester, null: false
      t.string :grade
      t.decimal :grade_weight, precision: 3, scale: 1
      t.string :source, null: false, default: "manual"
      t.timestamps
    end

    add_index :enrollments, [:student_id, :course_id, :year, :semester],
              unique: true, name: "idx_enrollments_unique_student_course_term"
  end
end
