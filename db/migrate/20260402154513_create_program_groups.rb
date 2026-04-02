class CreateProgramGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :program_groups do |t|
      t.string :code, null: false
      t.string :name_en, null: false
      t.string :name_th
      t.string :degree_level, null: false
      t.string :degree_name, null: false
      t.string :degree_name_th
      t.string :field_of_study, null: false
      t.timestamps
    end

    add_index :program_groups, :code, unique: true

    add_reference :programs, :program_group, foreign_key: true, null: true
  end
end
