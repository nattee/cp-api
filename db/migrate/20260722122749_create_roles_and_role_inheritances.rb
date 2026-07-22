class CreateRolesAndRoleInheritances < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :description
      # MySQL json columns cannot have defaults; the model normalizes nil → [].
      t.json :permission_keys
      t.boolean :locked, null: false, default: false
      t.timestamps
    end

    create_table :role_inheritances do |t|
      t.references :role, null: false, foreign_key: true
      t.references :parent_role, null: false, foreign_key: { to_table: :roles }
      t.timestamps
    end
    add_index :role_inheritances, [:role_id, :parent_role_id], unique: true
  end
end
