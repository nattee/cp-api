require "test_helper"

class LlmEval::RegistryBuilderTest < ActiveSupport::TestCase
  test "current variant returns the live registry" do
    defs = LlmEval::RegistryBuilder.build("current")
    assert_equal Line::ToolRegistry.definitions.size, defs.size
    assert_includes defs.map { |d| d.dig(:function, :name) }, "student_lookup"
  end

  test "candidate variant adds the four round-2 tools" do
    names = LlmEval::RegistryBuilder.build("candidate").map { |d| d.dig(:function, :name) }
    %w[student_grades course_enrollment semester_overview room_schedule].each do |tool|
      assert_includes names, tool
    end
    assert_equal names.uniq.size, names.size, "no duplicate tool names"
  end

  test "candidate variant skips tools that are already registered" do
    Line::ToolRegistry.register("student_grades",
      definition: Line::Tools::StudentGradesTool::DEFINITION,
      handler: Line::Tools::StudentGradesTool)
    names = LlmEval::RegistryBuilder.build("candidate").map { |d| d.dig(:function, :name) }
    assert_equal 1, names.count("student_grades")
  ensure
    Line::ToolRegistry.reset!
    Rails.application.reloader.reload!
  end

  test "decoy_count pads with decoys in OpenAI format" do
    base = LlmEval::RegistryBuilder.build("candidate")
    padded = LlmEval::RegistryBuilder.build("candidate", decoy_count: 5)
    assert_equal base.size + 5, padded.size

    decoy = padded.last
    assert_equal "function", decoy[:type]
    assert decoy.dig(:function, :name).present?
    assert decoy.dig(:function, :description).present?
    assert decoy.dig(:function, :parameters).present?
  end

  test "every decoy parses into a sane schema" do
    decoys = YAML.load_file(Rails.root.join("test/llm_eval/decoy_tools.yml"))
    assert_equal 13, decoys.size
    decoys.each do |d|
      assert d["name"].present?, "decoy missing name"
      assert d["description"].is_a?(String) && d["description"].present?, "#{d['name']}: bad description"
      (d.dig("parameters", "properties") || {}).each do |prop, schema|
        assert_equal [], schema.keys - %w[type description], "#{d['name']}.#{prop}: unexpected keys #{schema.keys.inspect} — unquoted comma in flow mapping?"
        assert schema["description"].is_a?(String) && schema["description"].present?, "#{d['name']}.#{prop}: description not a clean string"
      end
    end
  end

  test "unknown variant raises" do
    assert_raises(ArgumentError) { LlmEval::RegistryBuilder.build("bogus") }
  end
end
