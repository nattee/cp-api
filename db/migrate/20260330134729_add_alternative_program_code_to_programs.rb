class AddAlternativeProgramCodeToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :alternative_program_code, :string
  end
end
