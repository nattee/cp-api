class CreateScrapes < ActiveRecord::Migration[8.1]
  def change
    create_table :scrapes do |t|
      t.references :semester, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :source, null: false
      t.string :study_program, null: false, default: "S"
      t.string :state, null: false, default: "pending"
      t.integer :total_courses, default: 0
      t.integer :courses_found, default: 0
      t.integer :courses_not_found, default: 0
      t.integer :sections_count, default: 0
      t.integer :time_slots_count, default: 0
      t.json :unresolved_teachers
      t.json :error_log
      t.text :error_message
      t.timestamps
    end
  end
end
