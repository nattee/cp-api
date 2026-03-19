class AddDegreeNameThToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :degree_name_th, :string
  end
end
