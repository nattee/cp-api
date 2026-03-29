class AddResponseTimeToApiEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :api_events, :response_time_ms, :integer
  end
end
