require "test_helper"

class DataProvenanceSummaryTest < ActiveSupport::TestCase
  test "counts by source and totals" do
    Student.create!(student_id: "B30-CP01-001", first_name_th: "ก", last_name_th: "ข", admission_year_be: 2517,
                    status: "unknown", source: "book30", program: programs(:cp_bachelor))
    s = DataProvenance::Summary.new
    assert_equal 1, s.students_by_source["book30"]
    assert_equal Student.count, s.students_by_source.values.sum
    assert_equal Grade.count, s.grades_by_source.values.sum
    assert_equal Course.count, s.courses_by_generation.values.sum
    assert_equal ProgramGroup.count, s.counts[:program_groups]
    assert_equal 1, s.book[:students]
    assert_kind_of Array, s.imports
    assert_kind_of Array, s.scrapes
  end
end
