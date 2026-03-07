class AddLineLinkTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :line_link_token, :string
    add_column :users, :line_link_token_expires_at, :datetime
    add_index :users, :line_link_token, unique: true
  end
end
