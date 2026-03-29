class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :building, null: false
      t.string :room_number, null: false
      t.string :room_type
      t.integer :capacity

      t.timestamps
    end

    add_index :rooms, [:building, :room_number], unique: true
  end
end
