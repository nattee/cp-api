class AddCbStatusCodeToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :cb_status_code, :string
  end
end
