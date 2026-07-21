require "test_helper"

class LlmEval::ScorerTest < ActiveSupport::TestCase
  CASE_SINGLE = {
    "id" => "t1", "group" => "existing", "question" => "q",
    "accept" => [ { "tool" => "student_lookup", "params" => { "query" => "6732100021" } } ]
  }.freeze

  CASE_MULTI = {
    "id" => "t2", "group" => "new", "question" => "q",
    "accept" => [
      { "tool" => "course_enrollment", "params" => { "course_no" => "2110499" } },
      { "tool" => "student_grades", "params" => { "query" => "6732100021" } }
    ]
  }.freeze

  CASE_NONE = {
    "id" => "t3", "group" => "none", "question" => "q",
    "accept" => [ { "tool" => "none" } ]
  }.freeze

  def tool_call(name, args)
    { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }
  end

  test "exact tool and params pass" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("student_lookup", { query: "6732100021" }))
    assert s[:tool_ok]
    assert s[:params_ok]
    assert_equal [], s[:misses]
  end

  test "string params match by case-insensitive containment" do
    kase = { "accept" => [ { "tool" => "staff_lookup", "params" => { "query" => "ณัฐ" } } ] }
    s = LlmEval::Scorer.score(kase, tool_call("staff_lookup", { query: "อ.ณัฐ" }))
    assert s[:params_ok]
  end

  test "integer expected matches string actual" do
    kase = { "accept" => [ { "tool" => "cohort_gpa", "params" => { "admission_year" => 2565 } } ] }
    s = LlmEval::Scorer.score(kase, tool_call("cohort_gpa", { admission_year: "2565" }))
    assert s[:params_ok]
  end

  test "wrong tool fails" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("search", { query: "6732100021" }))
    refute s[:tool_ok]
    assert_equal "search", s[:called_tool]
  end

  test "missing param is reported" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("student_lookup", { program_code: "CP" }))
    assert s[:tool_ok]
    refute s[:params_ok]
    assert_equal [ "query" ], s[:misses]
  end

  test "any accept alternative passes" do
    s = LlmEval::Scorer.score(CASE_MULTI, tool_call("student_grades", { query: "6732100021" }))
    assert s[:tool_ok]
    assert s[:params_ok]
  end

  test "nil tool_call scores as none" do
    s = LlmEval::Scorer.score(CASE_NONE, nil)
    assert s[:tool_ok]
    assert s[:params_ok]

    s2 = LlmEval::Scorer.score(CASE_SINGLE, nil)
    refute s2[:tool_ok]
    assert_equal "none", s2[:called_tool]
  end

  test "unparseable arguments JSON fails params but not tool" do
    call = { "id" => "c1", "function" => { "name" => "student_lookup", "arguments" => "not json" } }
    s = LlmEval::Scorer.score(CASE_SINGLE, call)
    assert s[:tool_ok]
    refute s[:params_ok]
  end
end
