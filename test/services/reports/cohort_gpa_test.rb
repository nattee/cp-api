require "test_helper"

class Reports::CohortGpaTest < ActiveSupport::TestCase
  # Isolated records; cohort year 2599 avoids fixture students (2565-2567).
  setup do
    course = Course.create!(course_no: "9950001", name: "Cohort Course", revision_year_be: 2566, credits: 3)
    s1 = make_student("9900000501")
    s2 = make_student("9900000502")
    Grade.create!(student: s1, course: course, year_ce: 2022, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: s2, course: course, year_ce: 2022, semester: 1,
                  grade: "B", grade_weight: 3.0, source: "imported")
  end

  test "one row per term with GPA and GPAX stats, term labels in B.E." do
    result = Reports::CohortGpa.new(
      "program_group" => "CP", "admission_year" => "2599"
    ).run

    labels = result.columns.map { |c| c[:label] }
    assert_equal "Term", labels.first
    assert_includes labels, "GPA avg"
    assert_includes labels, "GPAX +2SD"
    assert_equal 14, labels.size

    row = result.rows.first
    assert_equal "2565/1", row[:term]   # year_ce 2022 + 543
    assert_equal 2, row[:n]
    assert_in_delta 3.5, row[:gpa_avg], 0.001
    assert_in_delta 3.5, row[:gpax_avg], 0.001
  end

  test "chart has band-upper/band-lower/avg/dashed-GPAX datasets" do
    result = Reports::CohortGpa.new(
      "program_group" => "CP", "admission_year" => "2599"
    ).run

    assert_equal "gpa-trend", result.chart[:type]
    datasets = result.chart[:data][:datasets]
    assert_equal [ "band-upper", "band-lower", nil, nil ], datasets.map { |d| d[:role] }
    assert datasets.last[:dashed]
    assert_equal [ "2565/1" ], result.chart[:data][:labels]
  end

  test "unknown program group returns an empty result" do
    result = Reports::CohortGpa.new(
      "program_group" => "ZZ", "admission_year" => "2599"
    ).run
    assert result.empty?
    assert_nil result.chart
  end

  test "is registered" do
    assert_equal Reports::CohortGpa, Reports::Registry.find("cohort_gpa")
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end
end
