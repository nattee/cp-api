class AddDebugToolCallsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :debug_tool_calls, :boolean, default: false, null: false
  end
end
