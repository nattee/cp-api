require "test_helper"

class Line::Tools::CourseEnrollmentToolTest < ActiveSupport::TestCase
  # Fixture grades for 2110101 (intro_computing): active_student 2024/1,
  # graduated_student 2022/1 — both CP.

  test "counts enrollment for a year with program × cohort breakdown" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "2110101", "year" => 2567 }))

    assert_equal 2567, result["year_be"]
    assert_equal 1, result["total"]
    assert_equal [ { "program" => "CP", "admission_year_be" => 2567, "cohort" => "CP51", "count" => 1 } ],
                 result["by_program_cohort"]
  end

  test "B.E. and C.E. years are equivalent" do
    be = JSON.parse(Line::Tools::CourseEnrollmentTool.call({ "course_no" => "2110101", "year" => 2567 }))
    ce = JSON.parse(Line::Tools::CourseEnrollmentTool.call({ "course_no" => "2110101", "year" => 2024 }))
    assert_equal be, ce
  end

  test "semester filter narrows the count" do
    with = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "2110101", "year" => 2567, "semester" => 2 }))
    assert_equal 0, with["total"]
  end

  test "student_query checks membership with section and grade" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "2110101", "year" => 2567, "student_query" => "6732100021" }))

    assert result["enrolled"]
    assert_equal "6732100021", result["student"]["student_id"]
    enrollment = result["enrollments"].first
    assert_equal "2567/1", enrollment["term"]
    assert_equal "A", enrollment["grade"]
  end

  test "student_query for a student who did not take the course" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "2110101", "year" => 2567, "student_query" => "6532100071" }))

    refute result["enrolled"]
    assert_equal [], result["enrollments"]
  end

  test "student_query matches a full Thai name via CONCAT" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "2110101", "year" => 2567, "student_query" => "ธนวัฒน์ ศรีเจริญ" }))

    assert result["enrolled"]
    assert_equal "6732100021", result["student"]["student_id"]
  end

  test "missing required params return error" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call({ "course_no" => "2110101" }))
    assert_match(/required/, result["error"])
  end

  test "unknown course_no returns error" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call({ "course_no" => "9999999", "year" => 2567 }))
    assert_match(/No course found/, result["error"])
  end

  test "by_program_cohort row has nil cohort when the program group has no epoch" do
    course = Course.create!(course_no: "9970002", name: "Enrollment Tool Course",
                            revision_year_be: 2566, credits: 3)
    student = Student.create!(student_id: "9900001201", first_name: "No", last_name: "Epoch",
                              first_name_th: "ไม่มี", last_name_th: "รุ่น",
                              admission_year_be: 2560, status: "active", program: Program.placeholder)
    Grade.create!(student: student, course: course, year_ce: 2017, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")

    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      { "course_no" => "9970002", "year" => 2560 }))

    row = result["by_program_cohort"].first
    assert row.key?("cohort")
    assert_nil row["cohort"]
  end
end
