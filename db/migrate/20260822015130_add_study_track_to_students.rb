class AddStudyTrackToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :study_track, :string
  end
end
