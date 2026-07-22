class AddFirstIntakeYearBeToProgramGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :program_groups, :first_intake_year_be, :integer
  end
end
