class AddDegreeAbbrToProgramGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :program_groups, :degree_abbr, :string
  end
end
