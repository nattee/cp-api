class AddMappingFieldsToDataImports < ActiveRecord::Migration[8.1]
  def change
    add_column :data_imports, :sheet_name, :string
    add_column :data_imports, :column_mapping, :json
  end
end
