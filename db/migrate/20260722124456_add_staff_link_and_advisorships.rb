class AddStaffLinkAndAdvisorships < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :staff, foreign_key: true

    create_table :advisorships do |t|
      t.references :student, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :started_on, null: false
      t.date :ended_on
      t.string :note
      t.timestamps
    end
    add_index :advisorships, [:student_id, :staff_id, :ended_on]
  end
end
