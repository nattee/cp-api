class AddSectionIdToGrades < ActiveRecord::Migration[8.1]
  def change
    add_reference :grades, :section, null: true, foreign_key: true
  end
end
