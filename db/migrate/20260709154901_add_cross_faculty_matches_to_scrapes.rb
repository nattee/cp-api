class AddCrossFacultyMatchesToScrapes < ActiveRecord::Migration[8.1]
  def change
    add_column :scrapes, :cross_faculty_matches, :json
  end
end
