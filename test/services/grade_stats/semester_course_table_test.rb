require "test_helper"

class GradeStats::SemesterCourseTableTest < ActiveSupport::TestCase
  # Isolated records (see course_distribution_test.rb for why). year_ce 2030
  # avoids the fixture grades (2022/2024) attached to cp_bachelor's courses.
  setup do
    @in1a = Course.create!(course_no: "9920001", name: "In (old rev)", revision_year_be: 2560, credits: 3)
    @in1b = Course.create!(course_no: "9920001", name: "In (new rev)", revision_year_be: 2566, credits: 3)
    @in2  = Course.create!(course_no: "9920002", name: "Also in", revision_year_be: 2566, credits: 3)
    @out  = Course.create!(course_no: "9920003", name: "Not in program", revision_year_be: 2566, credits: 3)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in1a)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in1b)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in2)

    @s1, @s2, @s3 = (1..3).map { |i| make_student("99000002#{i.to_s.rjust(2, '0')}") }
    grade(@s1, @in1a, "A", 4.0)   # old revision …
    grade(@s2, @in1b, "F", 0.0)   # … and new revision must merge into one row
    grade(@s3, @in2,  "B+", 3.5)
    grade(@s1, @out,  "A", 4.0)   # outside the program — must not appear
  end

  test "one row per course_no in the program group, revisions merged" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    assert_equal %w[9920001 9920002], r[:rows].map { |row| row[:course_no] }
    merged = r[:rows].first
    assert_equal({ "A" => 1, "F" => 1 }, merged[:counts])
    assert_equal 2, merged[:total]
    assert_equal "In (new rev)", merged[:name]  # latest revision's name
  end

  test "grade_columns is the GRADES-ordered union of grades present" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    assert_equal %w[A B+ F], r[:grade_columns]
  end

  test "per-course GPA uses sample SD and rounds to 2 decimals" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    merged = r[:rows].first
    assert_equal 2, merged[:gpa][:n]
    assert_in_delta 2.0, merged[:gpa][:mean], 0.001   # (4 + 0) / 2
    assert_in_delta 2.83, merged[:gpa][:sd], 0.001    # sample SD of [4, 0]
    single = r[:rows].second
    assert_nil single[:gpa][:sd]                      # STDDEV_SAMP is NULL for n=1
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, letter, weight)
    Grade.create!(student: student, course: course, year_ce: 2030, semester: 1,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
