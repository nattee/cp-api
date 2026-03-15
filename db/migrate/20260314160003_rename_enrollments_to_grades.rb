class RenameEnrollmentsToGrades < ActiveRecord::Migration[8.1]
  def change
    rename_table :enrollments, :grades
  end
end
