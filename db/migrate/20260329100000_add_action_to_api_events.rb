class AddActionToApiEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :api_events, :action, :string
  end
end
