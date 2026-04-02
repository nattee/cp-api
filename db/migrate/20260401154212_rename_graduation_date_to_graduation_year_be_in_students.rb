class RenameGraduationDateToGraduationYearBeInStudents < ActiveRecord::Migration[8.1]
  def change
    remove_column :students, :graduation_date, :date
    add_column :students, :graduation_year_be, :integer
  end
end
