class AddShortNameToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :short_name, :string
  end
end
