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

  test "returns per-term GPS/GPAX; B.E. and C.E. admission years are equivalent" do
    be = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "CP", "admission_year" => 2599))
    ce = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "cp", "admission_year" => 2056))

    assert_equal be, ce                       # era rule + case-insensitive code
    assert_equal "CP", be["program"]
    assert_equal 2599, be["admission_year_be"]
    term = be["terms"].first
    assert_equal "2565/1", term["term"]
    assert_in_delta 3.5, term["gps"]["avg"], 0.001
    assert_in_delta 3.5, term["gpax"]["avg"], 0.001
  end

  test "unknown program code returns an error listing valid codes" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "ZZ", "admission_year" => 2599))

    assert_match(/Unknown program code ZZ/, result["error"])
    assert_match(/CP/, result["error"])
  end
end
