class AddDescriptionToCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :courses, :description, :text
    add_column :courses, :description_th, :text
  end
end
