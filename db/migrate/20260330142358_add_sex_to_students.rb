class AddSexToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :sex, :string
  end
end
