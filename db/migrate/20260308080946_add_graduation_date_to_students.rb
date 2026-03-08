class AddGraduationDateToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :graduation_date, :date
  end
end
