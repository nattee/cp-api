class CreateChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_messages do |t|
      t.string :line_user_id
      t.string :role
      t.text :content
      t.json :tool_calls
      t.string :tool_call_id

      t.timestamps
    end
    add_index :chat_messages, [:line_user_id, :created_at]
  end
end
