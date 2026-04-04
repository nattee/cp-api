class CreateLineContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :line_contacts do |t|
      t.string :line_user_id, null: false
      t.string :display_name
      t.json :recent_messages
      t.integer :message_count, default: 0, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :line_contacts, :line_user_id, unique: true
  end
end
