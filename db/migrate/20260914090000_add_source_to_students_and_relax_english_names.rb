class AddSourceToStudentsAndRelaxEnglishNames < ActiveRecord::Migration[8.1]
  def up
    add_column :students, :source, :string, null: false, default: "imported"
    add_index :students, :source
    # The 30-year book gives Thai names only; students recorded from the book must be storable without English names.
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
    # Students recorded from the book have no English names; the NOT NULL constraints cannot
    # come back while they exist, and MySQL DDL is not transactional — fail before touching anything.
    if Student.where("first_name IS NULL OR last_name IS NULL").exists?
      raise ActiveRecord::IrreversibleMigration, "students with NULL English names exist; run `bin/rails book30:rollback COMMIT=1` first"
    end
    change_column_null :students, :first_name, false
    change_column_null :students, :last_name, false
    remove_index :students, :source
    remove_column :students, :source
  end
end
