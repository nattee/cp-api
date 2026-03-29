class AddInitialsToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :initials, :string
    add_index :staffs, :initials, unique: true
  end
end
