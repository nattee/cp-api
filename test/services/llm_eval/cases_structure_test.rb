require "test_helper"

class LlmEval::CasesStructureTest < ActiveSupport::TestCase
  KNOWN_TOOLS = %w[
    student_lookup staff_lookup course_lookup course_offering_lookup search
    grade_distribution cohort_gpa cohort_ranking
    student_grades course_enrollment semester_overview room_schedule
    missing_enrollments program_lookup
    none
  ].freeze

  test "every eval case is structurally valid" do
    cases = YAML.load_file(Rails.root.join("test/llm_eval/cases.yml"))
    assert_equal 59, cases.size
    assert_equal cases.size, cases.map { |c| c["id"] }.uniq.size, "duplicate case ids"

    cases.each do |c|
      assert c["id"].present?, "case missing id"
      assert %w[existing new none].include?(c["group"]), "#{c['id']}: bad group #{c['group'].inspect}"
      assert c["question"].is_a?(String) && c["question"].present?, "#{c['id']}: bad question"
      assert c["accept"].is_a?(Array) && c["accept"].any?, "#{c['id']}: accept must be a non-empty list"

      c["accept"].each do |alt|
        assert KNOWN_TOOLS.include?(alt["tool"]), "#{c['id']}: unknown tool #{alt['tool'].inspect}"
        next unless alt.key?("params")
        assert alt["params"].is_a?(Hash) && alt["params"].any?, "#{c['id']}: params must be a non-empty hash when present"
      end
    end
  end
end
