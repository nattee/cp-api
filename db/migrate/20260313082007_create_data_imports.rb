class CreateDataImports < ActiveRecord::Migration[8.1]
  def change
    create_table :data_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :target_type, null: false
      t.string :mode, null: false
      t.string :state, null: false
      t.integer :total_rows, default: 0
      t.integer :created_count, default: 0
      t.integer :updated_count, default: 0
      t.integer :error_count, default: 0
      t.json :row_errors
      t.text :error_message

      t.timestamps
    end

    add_index :data_imports, :state
    add_index :data_imports, :target_type
  end
end
