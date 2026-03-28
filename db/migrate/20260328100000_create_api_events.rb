class CreateApiEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :api_events do |t|
      t.string :source, null: false
      t.string :severity, null: false, default: "error"
      t.string :message, null: false
      t.json :details
      t.datetime :created_at, null: false
    end

    add_index :api_events, :created_at
    add_index :api_events, [:source, :created_at]
  end
end
