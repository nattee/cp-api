require "test_helper"

# Guards the cohort-dialect wording against per-tool drift: every registered
# tool exposing a `generation` parameter must carry the full shared teaching
# text (the anti-"CP51 = year 2551" guard included), not a hand-copied variant.
class Line::Tools::CohortParamDescriptionsTest < ActiveSupport::TestCase
  test "every generation param uses the shared description" do
    with_generation = Line::ToolRegistry.definitions.filter_map do |d|
      props = d.dig(:function, :parameters, :properties)
      [ d.dig(:function, :name), props[:generation][:description] ] if props&.key?(:generation)
    end

    assert_operator with_generation.size, :>=, 4, "expected at least 4 cohort-capable tools"
    with_generation.each do |name, description|
      assert description.start_with?(Line::Tools::CohortParam::GENERATION_DESCRIPTION),
             "#{name}: generation description drifted from the shared constant"
    end
  end

  test "every cohort-capable admission_year warns against label-derived years" do
    Line::ToolRegistry.definitions.each do |d|
      props = d.dig(:function, :parameters, :properties)
      next unless props&.key?(:generation)

      assert_includes props[:admission_year][:description],
                      Line::Tools::CohortParam::ADMISSION_YEAR_LABEL_WARNING,
                      "#{d.dig(:function, :name)}: admission_year lost the label warning"
    end
  end
end
