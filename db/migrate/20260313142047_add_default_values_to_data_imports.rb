class AddDefaultValuesToDataImports < ActiveRecord::Migration[8.1]
  def change
    add_column :data_imports, :default_values, :json
  end
end
