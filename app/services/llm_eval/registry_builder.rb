module LlmEval
  # Builds the OpenAI tools array for an eval variant:
  #   "current"   — exactly what ToolRegistry has registered (production view)
  #   "candidate" — current + the round-2 definitions not yet registered
  # decoy_count pads with definition-only fake tools from decoy_tools.yml for
  # the breaking-point sweep (accuracy vs. registry size).
  class RegistryBuilder
    CANDIDATE_TOOLS = {
      "student_grades"    => "Line::Tools::StudentGradesTool",
      "course_enrollment" => "Line::Tools::CourseEnrollmentTool",
      "semester_overview" => "Line::Tools::SemesterOverviewTool",
      "room_schedule"     => "Line::Tools::RoomScheduleTool"
    }.freeze

    DECOY_FILE = "test/llm_eval/decoy_tools.yml"

    def self.build(variant, decoy_count: 0)
      defs =
        case variant
        when "current"
          Line::ToolRegistry.definitions
        when "candidate"
          registered = Line::ToolRegistry.definitions
          registered_names = registered.map { |d| d.dig(:function, :name) }
          extra = CANDIDATE_TOOLS.reject { |name, _| registered_names.include?(name) }
          registered + extra.map { |name, klass| wrap(name, klass.constantize::DEFINITION) }
        else
          raise ArgumentError, "unknown registry variant '#{variant}' (use current|candidate)"
        end

      defs + decoys.first(decoy_count).map { |d| wrap(d["name"], d.except("name").deep_symbolize_keys) }
    end

    def self.wrap(name, definition)
      { type: "function", function: { name: name }.merge(definition) }
    end
    private_class_method :wrap

    def self.decoys
      YAML.load_file(Rails.root.join(DECOY_FILE))
    end
    private_class_method :decoys
  end
end
