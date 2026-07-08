require "test_helper"

class Reports::SemesterGradeDistributionTest < ActiveSupport::TestCase
  # Isolated records (LINE lookup-tool tests assert exact fixture counts).
  # year_ce 2030 = B.E. 2573 avoids fixture grades.
  setup do
    @course = Course.create!(course_no: "9940001", name: "Report Course", revision_year_be: 2566, credits: 3)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @course)
    s1 = make_student("9900000401")
    s2 = make_student("9900000402")
    Grade.create!(student: s1, course: @course, year_ce: 2030, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: s2, course: @course, year_ce: 2030, semester: 1,
                  grade: "B+", grade_weight: 3.5, source: "imported")
  end

  test "builds dynamic grade columns and a chart from the term's data (B.E. input)" do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "CP", "year" => "2573", "term" => "1"
    ).run

    assert_equal [ "Course No", "Name", "N", "A", "B+", "GPA", "SD" ],
                 result.columns.map { |c| c[:label] }
    row = result.rows.find { |r| r[:course_no] == "9940001" }
    assert_equal 1, row[:g_a]
    assert_equal 1, row[:g_bp]
    assert_equal 2, row[:total]
    assert_in_delta 3.75, row[:gpa], 0.001

    assert_equal "horizontal-stacked-bar", result.chart[:type]
    assert_equal "grade", result.chart[:data][:colorBy]
    assert_includes result.chart[:data][:labels], "9940001"
  end

  test "treats the year param as Buddhist Era, not C.E." do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "CP", "year" => "2030", "term" => "1"
    ).run
    assert_empty result.rows
  end

  test "unknown program group returns an empty result, and no chart when empty" do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "ZZ", "year" => "2573", "term" => "1"
    ).run
    assert result.empty?
    assert_nil result.chart
  end

  test "is registered" do
    assert_equal Reports::SemesterGradeDistribution,
                 Reports::Registry.find("semester_grade_distribution")
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end
end
