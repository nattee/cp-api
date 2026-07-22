require "test_helper"

class Line::Tools::CohortRankingToolTest < ActiveSupport::TestCase
  # Isolated cohort; year 2599 (B.E.) avoids fixture students. Uses cp_group's
  # first_intake_year_be 2517 -> generation 83 resolves to 2599.
  setup do
    course = Course.create!(course_no: "9950001", name: "Cohort Ranking Course",
                            revision_year_be: 2566, credits: 3)
    @top = Student.create!(student_id: "9900000501", first_name: "T", last_name: "S",
                           first_name_th: "ท", last_name_th: "ส",
                           admission_year_be: 2599, status: "active",
                           program: programs(:cp_bachelor))
    Grade.create!(student: @top, course: course, year_ce: 2022, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
  end

  test "ranks top students of a cohort by generation" do
    result = JSON.parse(Line::Tools::CohortRankingTool.call({ "program_code" => "CP", "generation" => 83 }))

    assert_equal "CP", result["program"]
    assert_equal 2599, result["admission_year_be"]
    assert_equal "CP83", result["cohort"]
    top = result["ranking"].first
    assert_equal 1, top["rank"]
    assert_equal @top.student_id, top["student_id"]
    assert_equal 4.0, top["gpax"]
  end

  test "limit clamps to MAX_LIMIT" do
    result = JSON.parse(Line::Tools::CohortRankingTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "limit" => 100 }))

    assert_operator result["ranking"].size, :<=, Line::Tools::CohortRankingTool::MAX_LIMIT
  end

  test "unknown program code returns an error listing valid codes" do
    result = JSON.parse(Line::Tools::CohortRankingTool.call(
      { "program_code" => "ZZ", "admission_year" => 2599 }))

    assert_match(/Unknown program code ZZ/, result["error"])
    assert_match(/CP/, result["error"])
  end

  test "neither admission_year nor generation returns an error" do
    result = JSON.parse(Line::Tools::CohortRankingTool.call({ "program_code" => "CP" }))

    assert_match(/admission_year or generation is required/, result["error"])
  end

  test "empty cohort returns a note and empty ranking" do
    result = JSON.parse(Line::Tools::CohortRankingTool.call(
      { "program_code" => "CP", "admission_year" => 2600 }))

    assert_empty result["ranking"]
    assert_equal "No graded students found for this cohort.", result["note"]
    assert result.key?("cohort")
  end
end
