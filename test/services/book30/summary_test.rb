require "test_helper"

class Book30SummaryTest < ActiveSupport::TestCase
  setup do
    @cp = program_groups(:cp_group)
    @prog = programs(:cp_bachelor) # year_started 2540, group CP
    @linked = Student.create!(student_id: "4031000021", first_name: "A", last_name: "B", first_name_th: "ก", last_name_th: "ข",
                              admission_year_be: 2540, status: "graduated", program: @prog)
    @unlisted = Student.create!(student_id: "4031000039", first_name: "C", last_name: "D", first_name_th: "ค", last_name_th: "ง",
                                admission_year_be: 2540, status: "graduated", program: @prog)
    @placeholder = Student.create!(student_id: "B30-CP24-002", first_name_th: "จ", last_name_th: "ฉ", admission_year_be: 2540,
                                   status: "unknown", source: "book30", program: @prog)
    Book30Entry.create!(cohort: "CP24", year_be: 2540, line_no: 1, raw_line: "นาย ก ข", first_name_th: "ก", last_name_th: "ข", outcome: "linked_exact", student: @linked)
    Book30Entry.create!(cohort: "CP24", year_be: 2540, line_no: 2, raw_line: "นาย จ ฉ", first_name_th: "จ", last_name_th: "ฉ", outcome: "create_missing", student: @placeholder)
    Book30Entry.create!(cohort: "CP24", year_be: 2540, line_no: 3, raw_line: "นาย ก ข", outcome: "duplicate_line")
  end

  test "totals, examples and per-cohort rows" do
    s = Book30::Summary.new
    assert s.any?
    assert_equal({ lines: 3, links: 1, creates: 1, ignored: 1, placeholders: 1 }, s.totals)
    assert_equal "linked_exact", s.examples["linked_exact"].outcome
    row = s.cohort_rows.find { |r| r.cohort == "CP24" }
    assert_equal [ 2540, 3, 2, 1 ], [ row.year, row.book, row.db, row.db_only ], "db counts exclude placeholders; db_only = unlisted student"
    assert_equal({ "linked_exact" => 1, "create_missing" => 1, "duplicate_line" => 1 }, row.counts.reject { |_, n| n.zero? })
    assert_equal [ "CP" ], s.group_rows.keys
  end

  test "empty state" do
    Book30Entry.delete_all
    assert_not Book30::Summary.new.any?
  end
end
