require "test_helper"

class Line::Tools::GradeDistributionToolTest < ActiveSupport::TestCase
  # Isolated records (the sibling lookup-tool tests assert exact fixture counts).
  setup do
    @course = Course.create!(course_no: "9960001", name: "Tool Course", name_th: "วิชาทดสอบ",
                             revision_year_be: 2566, credits: 3)
    student = Student.create!(student_id: "9900000601", first_name: "T", last_name: "S",
                              first_name_th: "ท", last_name_th: "ส",
                              admission_year_be: 2599, status: "active",
                              program: programs(:cp_bachelor))
    Grade.create!(student: student, course: @course, year_ce: 2025, semester: 2,
                  grade: "A", grade_weight: 4.0, source: "imported")
  end

  test "returns distribution and GPA; C.E. and B.E. years are equivalent" do
    ce = JSON.parse(Line::Tools::GradeDistributionTool.call(
      { "course_no" => "9960001", "year" => 2025, "semester" => 2 }))
    be = JSON.parse(Line::Tools::GradeDistributionTool.call(
      { "course_no" => "9960001", "year" => 2568, "semester" => 2 }))

    assert_equal ce, be
    assert_equal({ "A" => 1 }, ce["counts"])
    assert_equal 1, ce["total"]
    assert_equal "Tool Course", ce["name_en"]
    assert_equal 2025, ce["year_ce"]
    assert_in_delta 4.0, ce["gpa"]["mean"], 0.001
  end

  test "omitting semester returns every term of the year" do
    result = JSON.parse(Line::Tools::GradeDistributionTool.call(
      { "course_no" => "9960001", "year" => 2568 }))

    assert_equal 1, result["semesters"].size
    assert_equal 2, result["semesters"].first["semester"]
  end

  test "unknown course and missing params return errors" do
    assert_includes Line::Tools::GradeDistributionTool.call(
      { "course_no" => "0000000", "year" => 2568 }), "error"
    assert_includes Line::Tools::GradeDistributionTool.call(
      { "course_no" => "9960001" }), "error"
  end
end
