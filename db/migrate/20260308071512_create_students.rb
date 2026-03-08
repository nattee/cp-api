class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.string :student_id, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :first_name_th
      t.string :last_name_th
      t.string :email
      t.string :phone
      t.text :address
      t.string :discord
      t.string :line_id
      t.string :guardian_name
      t.string :guardian_phone
      t.string :previous_school
      t.string :enrollment_method
      t.integer :admission_year, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :students, :student_id, unique: true
    add_index :students, :admission_year
  end
end
