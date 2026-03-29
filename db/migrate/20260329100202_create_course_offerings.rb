class CreateCourseOfferings < ActiveRecord::Migration[8.1]
  def change
    create_table :course_offerings do |t|
      t.references :course, null: false, foreign_key: true
      t.references :semester, null: false, foreign_key: true
      t.string :status, null: false, default: "planned"
      t.text :remark

      t.timestamps
    end

    add_index :course_offerings, [:course_id, :semester_id], unique: true
  end
end
