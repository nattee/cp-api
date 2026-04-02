class AddOldProgramToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :old_program, :string
  end
end
