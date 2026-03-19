class AddProgramCodeToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :program_code, :string

    reversible do |dir|
      dir.up do
        # Backfill existing programs with their Rails ID as a temporary code
        execute "UPDATE programs SET program_code = LPAD(id, 4, '0') WHERE program_code IS NULL"
        change_column_null :programs, :program_code, false
      end
    end

    add_index :programs, :program_code, unique: true
  end
end
