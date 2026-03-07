class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "viewer"
      t.boolean :active, null: false, default: true
      t.string :provider
      t.string :uid
      t.datetime :last_sign_in_at

      t.timestamps
    end

    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
    add_index :users, %i[provider uid], unique: true
  end
end
