class CreateSections < ActiveRecord::Migration[8.1]
  def change
    create_table :sections do |t|
      t.references :course_offering, null: false, foreign_key: true
      t.integer :section_number, null: false
      t.text :remark
      t.integer :enrollment_current
      t.integer :enrollment_max

      t.timestamps
    end

    add_index :sections, [:course_offering_id, :section_number], unique: true
  end
end
