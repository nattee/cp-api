class CreateStaffPrograms < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_programs do |t|
      t.references :staff, null: false, foreign_key: true
      t.references :program, null: false, foreign_key: true
      t.string :role
      t.date :start_date
      t.date :end_date

      t.timestamps
    end
  end
end
