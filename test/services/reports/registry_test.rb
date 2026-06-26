require "test_helper"

class Reports::RegistryTest < ActiveSupport::TestCase
  test "for_program hides the thesis report for bachelor, shows it for master" do
    bachelor_keys = Reports::Registry.for_program(program_groups(:cp_group)).map(&:key)
    master_keys   = Reports::Registry.for_program(program_groups(:cm_group)).map(&:key)

    assert_not_includes bachelor_keys, "thesis_credits"
    assert_includes master_keys, "thesis_credits"

    # :all-program reports appear for both
    assert_includes bachelor_keys, "failing_students"
    assert_includes master_keys, "failing_students"
  end

  test "find returns the report class by key, nil for unknown" do
    assert_equal Reports::FailingStudents, Reports::Registry.find("failing_students")
    assert_nil Reports::Registry.find("nonexistent")
  end

  test "grouped buckets reports by section in SECTIONS order" do
    keys = Reports::Registry.grouped.keys
    assert_equal keys.sort_by { |k| Reports::Registry::SECTIONS.keys.index(k) }, keys
    assert_includes Reports::Registry.grouped[:courses].map(&:key), "course_teachers"
  end
end
