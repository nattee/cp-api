require "test_helper"

class Line::Tools::MissingEnrollmentsToolTest < ActiveSupport::TestCase
  # Isolated cohort; admission_year_be 2599 avoids fixture students. Two
  # courses (A/B, 997xxxx ids) so per-course missing lists can differ.
  # s1: has A (B+) and B (A) -> satisfies both.
  # s2: has A (grade W) only -> not enrolled-satisfied for A; W does NOT
  #     satisfy needs_course either.
  # s3: has A with grade NULL only -> not enrolled-satisfied for A, but NULL
  #     (in-flight enrollment) DOES satisfy needs_course.
  # s4: no records at all -> missing both modes, both courses.
  # s5: retired, no records -> excluded by default (active-only) status filter.
  setup do
    @course_a = Course.create!(course_no: "9970001", name: "Missing Enrollments Course A",
                               revision_year_be: 2566, credits: 3)
    @course_b = Course.create!(course_no: "9970002", name: "Missing Enrollments Course B",
                               revision_year_be: 2566, credits: 3)

    @s1 = Student.create!(student_id: "9900001001", first_name: "One", last_name: "S",
                          first_name_th: "หนึ่ง", last_name_th: "ส",
                          admission_year_be: 2599, status: "active",
                          program: programs(:cp_bachelor))
    @s2 = Student.create!(student_id: "9900001002", first_name: "Two", last_name: "S",
                          first_name_th: "สอง", last_name_th: "ส",
                          admission_year_be: 2599, status: "active",
                          program: programs(:cp_bachelor))
    @s3 = Student.create!(student_id: "9900001003", first_name: "Three", last_name: "S",
                          first_name_th: "สาม", last_name_th: "ส",
                          admission_year_be: 2599, status: "active",
                          program: programs(:cp_bachelor))
    @s4 = Student.create!(student_id: "9900001004", first_name: "Four", last_name: "S",
                          first_name_th: "สี่", last_name_th: "ส",
                          admission_year_be: 2599, status: "active",
                          program: programs(:cp_bachelor))
    @s5 = Student.create!(student_id: "9900001005", first_name: "Five", last_name: "S",
                          first_name_th: "ห้า", last_name_th: "ส",
                          admission_year_be: 2599, status: "retired",
                          program: programs(:cp_bachelor))

    Grade.create!(student: @s1, course: @course_a, year_ce: 2022, semester: 1,
                  grade: "B+", grade_weight: 3.5, source: "imported")
    Grade.create!(student: @s1, course: @course_b, year_ce: 2022, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: @s2, course: @course_a, year_ce: 2022, semester: 1,
                  grade: "W", grade_weight: nil, source: "imported")
    Grade.create!(student: @s3, course: @course_a, year_ce: 2022, semester: 1,
                  grade: nil, grade_weight: nil, source: "imported")
  end

  test "mode enrolled (default): missing = no Grade row at all, active only" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9970001", "9970002" ] }))

    assert_equal "enrolled", result["mode"]
    assert_equal "active", result["status_filter"]
    assert_equal 4, result["cohort_size"] # s5 (retired) excluded

    students_by_id = result["students"].index_by { |s| s["student_id"] }
    assert_not students_by_id.key?(@s1.student_id) # has both
    # s2 and s3 each already have a Grade row for course A (W and NULL grade
    # respectively) -- "enrolled" mode only cares whether a row exists, so
    # neither is missing A; both are missing B (no row at all).
    assert_equal [ "9970002" ], students_by_id[@s2.student_id]["missing"]
    assert_equal [ "9970002" ], students_by_id[@s3.student_id]["missing"]
    assert_equal [ "9970001", "9970002" ], students_by_id[@s4.student_id]["missing"]
    assert_not students_by_id.key?(@s5.student_id)

    per_course = result["per_course"].index_by { |c| c["course_no"] }
    assert_equal 1, per_course["9970001"]["missing_count"] # s4
    assert_equal 3, per_course["9970002"]["missing_count"] # s2, s3, s4
    assert_equal 3, result["missing_total"]
  end

  test "mode needs_course: NULL grade satisfies, F/W/U does not" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9970001" ],
        "mode" => "needs_course" }))

    assert_equal "needs_course", result["mode"]
    students_by_id = result["students"].index_by { |s| s["student_id"] }

    assert_not students_by_id.key?(@s3.student_id), "NULL-grade (in-flight) enrollment must satisfy needs_course"
    assert students_by_id.key?(@s2.student_id), "W grade must NOT satisfy needs_course"
    assert students_by_id.key?(@s4.student_id)

    per_course = result["per_course"].index_by { |c| c["course_no"] }
    assert_equal 2, per_course["9970001"]["missing_count"] # s2, s4
  end

  test "status all includes retired students and echoes status_filter" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9970001" ],
        "status" => "all" }))

    assert_equal "all", result["status_filter"]
    assert_equal 5, result["cohort_size"]
    students_by_id = result["students"].index_by { |s| s["student_id"] }
    assert students_by_id.key?(@s5.student_id)
  end

  test "unknown course_no returns an error" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9999999" ] }))

    assert_match(/No course found with course_no 9999999/, result["error"])
  end

  test "empty course_nos returns an error" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [] }))

    assert_match(/course_nos is required/, result["error"])
  end

  test "more than MAX_COURSES course_nos returns an error" do
    six_courses = (1..6).map { |i| "997000#{i}" }
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => six_courses }))

    assert_match(/Too many courses/, result["error"])
  end

  test "unknown program code returns an error listing valid codes" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "ZZ", "admission_year" => 2599, "course_nos" => [ "9970001" ] }))

    assert_match(/Unknown program code ZZ/, result["error"])
  end

  test "bad mode returns an error" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9970001" ],
        "mode" => "bogus" }))

    assert_match(/mode must be/, result["error"])
  end

  test "cohort label key is present" do
    result = JSON.parse(Line::Tools::MissingEnrollmentsTool.call(
      { "program_code" => "CP", "admission_year" => 2599, "course_nos" => [ "9970001" ] }))

    assert result.key?("cohort")
    assert_equal 2599, result["admission_year_be"]
  end
end
