class AddSourceToStudentsAndRelaxEnglishNames < ActiveRecord::Migration[8.1]
  def up
    add_column :students, :source, :string, null: false, default: "imported"
    add_index :students, :source
    # The 30-year book gives Thai names only; placeholders must be storable without English names.
    change_column_null :students, :first_name, true
    change_column_null :students, :last_name, true
    # Provenance backfill. Every student row in this database was created on one of two days:
    # 2026-04-12 (the Excel load of record) or 2026-07-05 (the ChulaBooster student sync).
    # CB-created rows all carry cb_status_code; Excel rows may too (it was mirrored later),
    # so the date is the discriminator. Rows created on any other day keep the default.
    execute <<~SQL
      UPDATE students
         SET source = 'chulabooster'
       WHERE DATE(created_at) = '2026-07-05'
         AND (cb_status_code IS NOT NULL OR remark LIKE 'ChulaBooster sync%')
    SQL
  end

  def down
    remove_index :students, :source
    remove_column :students, :source
    change_column_null :students, :first_name, false
    change_column_null :students, :last_name, false
  end
end
