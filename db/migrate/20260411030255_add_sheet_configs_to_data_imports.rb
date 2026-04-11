class AddSheetConfigsToDataImports < ActiveRecord::Migration[8.1]
  def change
    add_column :data_imports, :sheet_configs, :json
  end
end
