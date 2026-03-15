class AddCreditsGrantToEnrollments < ActiveRecord::Migration[8.1]
  def change
    add_column :enrollments, :credits_grant, :integer
  end
end
