class AddSkipFailuresToDataImports < ActiveRecord::Migration[8.1]
  def change
    add_column :data_imports, :skip_failures, :boolean, default: false, null: false
  end
end
