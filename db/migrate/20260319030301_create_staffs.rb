class CreateStaffs < ActiveRecord::Migration[8.0]
  def change
    create_table :staffs do |t|
      t.string :title, null: false
      t.string :academic_title
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :first_name_th
      t.string :last_name_th
      t.string :staff_type, null: false
      t.string :email
      t.string :phone
      t.date :birthdate
      t.date :employment_date
      t.string :room
      t.string :status, null: false, default: "active"

      t.timestamps
    end
  end
end
