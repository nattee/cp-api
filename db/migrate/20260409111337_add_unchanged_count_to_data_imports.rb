class AddUnchangedCountToDataImports < ActiveRecord::Migration[8.1]
  def change
    add_column :data_imports, :unchanged_count, :integer, default: 0
  end
end
