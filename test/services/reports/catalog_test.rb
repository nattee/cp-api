require "test_helper"

class Reports::CatalogTest < ActiveSupport::TestCase
  test "report keys are unique" do
    keys = Reports::Catalog.entries.map(&:key)
    assert_equal keys.uniq, keys
  end

  test "every framework report is present in the catalog" do
    Reports::Registry.all.each do |klass|
      assert Reports::Catalog.find(klass.key), "#{klass.key} missing from catalog"
    end
  end

  test "hub entries exclude the system section and are all hub?" do
    assert Reports::Catalog.hub_entries.none? { |e| e.section == :system }
    assert Reports::Catalog.hub_entries.all?(&:hub?)
  end

  test "data coverage is an admin-gated system report, absent from the hub" do
    dc = Reports::Catalog.find("data_coverage")
    assert_equal :system, dc.section
    assert_equal :admin, dc.access
    assert_not dc.hub?
    assert Reports::Catalog.hub_entries.none? { |e| e.key == "data_coverage" }
  end

  test "all hub entries are open to any logged-in user" do
    assert Reports::Catalog.hub_entries.all? { |e| e.access == :all }
  end

  test "registry entries wrap a report class; external entries carry a path helper" do
    Reports::Catalog.entries.each do |e|
      if e.registry?
        assert e.report_class < Reports::Base, "#{e.key} should wrap a Reports::Base subclass"
        assert_nil e.path_helper
      else
        assert_not_nil e.path_helper, "#{e.key} needs a path helper"
        assert_nil e.report_class
      end
    end
  end

  test "schedules vs teaching split is as designed" do
    assert_equal :schedules, Reports::Catalog.find("schedules_room").section
    assert_equal :teaching, Reports::Catalog.find("schedules_workload").section
    assert_equal "Staff Workload", Reports::Catalog.find("schedules_workload").title
  end

  test "the two grade-distribution reports have distinct titles" do
    assert_equal "Grade distribution by course", Reports::Catalog.find("semester_grade_distribution").title
    assert_equal "Class Grade Distribution", Reports::Catalog.find("grades_distribution").title
  end

  test "grouped orders sections per SECTIONS and omits system" do
    order = Reports::Catalog.grouped.keys
    assert_equal order, order.sort_by { |s| Reports::Catalog::SECTIONS.keys.index(s) }
    assert_not_includes order, :system
  end
end
