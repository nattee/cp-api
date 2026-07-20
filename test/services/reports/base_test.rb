require "test_helper"

class ReportsBaseTest < ActiveSupport::TestCase
  test "param records an explicit context opt-in" do
    year = Reports::SemesterGradeDistribution.params_spec.find { |p| p[:name] == :year }
    assert_equal :year, year[:context]
  end

  test "a param with no context opt-in carries nil" do
    prog = Reports::SemesterGradeDistribution.params_spec.find { |p| p[:name] == :program_group }
    assert_nil prog[:context]
  end

  test "admission_year params never opt in" do
    [Reports::CohortGpa, Reports::GroupCreditShortfall, Reports::ThesisCredits].each do |klass|
      adm = klass.params_spec.find { |p| p[:name] == :admission_year }
      assert_nil adm[:context], "#{klass}: admission_year must never draw from the sticky term"
    end
  end
end
