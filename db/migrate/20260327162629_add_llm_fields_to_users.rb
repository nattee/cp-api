class AddLlmFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :llm_consent, :boolean, default: false, null: false
    add_column :users, :llm_model, :string
  end
end
