class CreateTeachings < ActiveRecord::Migration[8.1]
  def change
    create_table :teachings do |t|
      t.references :section, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.decimal :load_ratio, precision: 3, scale: 2, null: false, default: 1.0

      t.timestamps
    end

    add_index :teachings, [:section_id, :staff_id], unique: true
  end
end
