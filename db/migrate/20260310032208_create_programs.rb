class CreatePrograms < ActiveRecord::Migration[8.1]
  def change
    create_table :programs do |t|
      t.string :name_en, null: false
      t.string :name_th
      t.string :degree_level, null: false
      t.string :degree_name, null: false
      t.string :field_of_study, null: false
      t.integer :year_started, null: false

      t.timestamps
    end
  end
end
