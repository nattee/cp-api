class RenameAdmissionYearToAdmissionYearBe < ActiveRecord::Migration[8.0]
  def change
    rename_column :students, :admission_year, :admission_year_be
  end
end
