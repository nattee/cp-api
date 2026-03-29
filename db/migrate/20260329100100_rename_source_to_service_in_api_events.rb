class RenameSourceToServiceInApiEvents < ActiveRecord::Migration[8.1]
  def change
    rename_column :api_events, :source, :service if column_exists?(:api_events, :source)
  end
end
