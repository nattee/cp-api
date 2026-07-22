require "test_helper"

class Line::Tools::CohortGpaToolTest < ActiveSupport::TestCase
  # Isolated records; cohort year 2599 (B.E.) = 2056 (C.E.) avoids fixtures.
  setup do
    course = Course.create!(course_no: "9970001", name: "Cohort Tool Course",
                            revision_year_be: 2566, credits: 3)
    student = Student.create!(student_id: "9900000701", first_name: "T", last_name: "S",
                              first_name_th: "ท", last_name_th: "ส",
                              admission_year_be: 2599, status: "active",
                              program: programs(:cp_bachelor))
    Grade.create!(student: student, course: course, year_ce: 2022, semester: 1,
                  grade: "B+", grade_weight: 3.5, source: "imported")
  end

  test "returns per-term GPA/GPAX; B.E. and C.E. admission years are equivalent" do
    be = JSON.parse(Line::Tools::CohortGpaTool.call(
      { "program_code" => "CP", "admission_year" => 2599 }))
    ce = JSON.parse(Line::Tools::CohortGpaTool.call(
      { "program_code" => "cp", "admission_year" => 2056 }))

    assert_equal be, ce                       # era rule + case-insensitive code
    assert_equal "CP", be["program"]
    assert_equal 2599, be["admission_year_be"]
    assert_equal "CP83", be["cohort"]
    term = be["terms"].first
    assert_equal "2565/1", term["term"]
    assert_in_delta 3.5, term["gpa"]["avg"], 0.001
    assert_in_delta 3.5, term["gpax"]["avg"], 0.001
  end

  test "unknown program code returns an error listing valid codes" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call(
      { "program_code" => "ZZ", "admission_year" => 2599 }))

    assert_match(/Unknown program code ZZ/, result["error"])
    assert_match(/CP/, result["error"])
  end

  # --- Cohort/generation notation (generation param) ---

  test "generation resolves to admission_year via program group epoch" do
    # program_groups(:cp_group) fixture has first_intake_year_be: 2517.
    # Generation 83 -> 2517 + 83 - 1 = 2599, matching the setup student's admission year.
    by_generation = JSON.parse(Line::Tools::CohortGpaTool.call({ "program_code" => "CP", "generation" => 83 }))
    by_year = JSON.parse(Line::Tools::CohortGpaTool.call({ "program_code" => "CP", "admission_year" => 2599 }))

    assert_equal by_year, by_generation
    assert_equal 2599, by_generation["admission_year_be"]
  end

  test "generation for a group without a recorded epoch returns an error" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call({ "program_code" => "OTHER", "generation" => 1 }))
    assert_match(/no recorded first intake year/, result["error"])
  end

  test "admission_year wins when both admission_year and generation are given" do
    by_both = JSON.parse(Line::Tools::CohortGpaTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "generation" => 1 }))

    assert_equal 2599, by_both["admission_year_be"]
  end

  test "neither admission_year nor generation returns an error" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call({ "program_code" => "CP" }))
    assert_match(/admission_year or generation is required/, result["error"])
  end

  test "cohort is nil when the program group has no epoch" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call(
      { "program_code" => "OTHER", "admission_year" => 2560 }))

    assert result.key?("cohort")
    assert_nil result["cohort"]
  end
end
