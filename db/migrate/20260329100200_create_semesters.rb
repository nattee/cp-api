class CreateSemesters < ActiveRecord::Migration[8.1]
  def change
    create_table :semesters do |t|
      t.integer :year_be, null: false
      t.integer :semester_number, null: false

      t.timestamps
    end

    add_index :semesters, [:year_be, :semester_number], unique: true
  end
end
