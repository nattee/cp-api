class CreateTimeSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :time_slots do |t|
      t.references :section, null: false, foreign_key: true
      t.references :room, null: true, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.string :remark

      t.timestamps
    end
  end
end
