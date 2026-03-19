class AddActiveTotalCreditToPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :programs, :active, :boolean, default: true, null: false
    add_column :programs, :total_credit, :integer
  end
end
