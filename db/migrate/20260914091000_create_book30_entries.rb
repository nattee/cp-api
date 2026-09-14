class CreateBook30Entries < ActiveRecord::Migration[8.1]
  def change
    # One row per printed line of the 30-year book's alumni directory: what the
    # line said, what was decided about it, and which student it links to or created.
    create_table :book30_entries do |t|
      t.string  :cohort,   null: false            # e.g. CP14
      t.integer :year_be,  null: false            # admission year implied by the cohort code
      t.integer :line_no,  null: false            # 1-based position within the cohort
      t.string  :raw_line, null: false            # as printed (after glyph decode)
      t.string  :first_name_th
      t.string  :last_name_th
      t.string  :alias_name                       # bracketed maiden name, if printed
      t.string  :sex                              # M/F from the title, if any
      t.string  :outcome,  null: false
      t.references :student, foreign_key: true, null: true
      t.text    :note
      t.timestamps
    end
    add_index :book30_entries, [:cohort, :line_no], unique: true
    add_index :book30_entries, :outcome
  end
end
