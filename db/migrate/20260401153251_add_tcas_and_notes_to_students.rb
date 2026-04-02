class AddTcasAndNotesToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :tcas, :string
    add_column :students, :status_note, :string
    add_column :students, :remark, :string
  end
end
