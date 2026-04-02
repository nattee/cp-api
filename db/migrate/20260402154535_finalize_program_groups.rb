class FinalizeProgramGroups < ActiveRecord::Migration[8.1]
  def change
    change_column_null :programs, :program_group_id, false

    remove_column :programs, :name_en, :string
    remove_column :programs, :name_th, :string
    remove_column :programs, :degree_level, :string
    remove_column :programs, :degree_name, :string
    remove_column :programs, :degree_name_th, :string
    remove_column :programs, :field_of_study, :string
  end
end
