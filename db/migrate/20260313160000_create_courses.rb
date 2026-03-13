class CreateCourses < ActiveRecord::Migration[8.1]
  def change
    create_table :courses do |t|
      t.string :name, null: false
      t.string :name_th
      t.string :name_abbr
      t.string :course_group
      t.string :course_no, null: false
      t.integer :revision_year, null: false
      t.references :program, null: false, foreign_key: true
      t.boolean :is_gened, default: false, null: false
      t.string :department_code
      t.integer :credits
      t.integer :l_credits
      t.integer :nl_credits
      t.integer :l_hours
      t.integer :nl_hours
      t.integer :s_hours
      t.boolean :is_thesis, default: false, null: false

      t.timestamps
    end

    add_index :courses, [:revision_year, :course_no], unique: true
  end
end
