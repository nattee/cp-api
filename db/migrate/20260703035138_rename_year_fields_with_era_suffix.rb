class RenameYearFieldsWithEraSuffix < ActiveRecord::Migration[8.1]
  def change
    rename_column :courses,  :revision_year, :revision_year_be
    rename_column :programs, :year_started,  :year_started_be
    rename_column :grades,   :year,          :year_ce

    # No explicit rename_index needed: rename_column automatically renames any
    # index whose name follows the index_<table>_on_<column> convention, so the
    # courses unique index becomes index_courses_on_revision_year_be_and_course_no
    # on its own. (grades' index has a custom name and is updated in place.)
    # An explicit rename_index here would raise on a fresh run — the old index
    # name no longer exists by the time it executes.
  end
end
