require "test_helper"

class Reports::FailingStudentsTest < ActiveSupport::TestCase
  # Build isolated records rather than fixtures: the LINE lookup-tool tests
  # assert exact fixture counts (e.g. "all courses == 3"), so report data lives
  # only inside this test's transaction.
  setup do
    @course = Course.create!(course_no: "9900001", name: "Test Course",
                             revision_year: 2565, program: programs(:cp_bachelor))
    @failed = make_student("9900000001")
    @passed = make_student("9900000002")
    Grade.create!(student: @failed, course: @course, year: 2023, semester: 1,
                  grade: "F", grade_weight: 0.0, credits_grant: 0, source: "imported")
    Grade.create!(student: @passed, course: @course, year: 2023, semester: 1,
                  grade: "A", grade_weight: 4.0, credits_grant: 3, source: "imported")
  end

  test "returns students with grade F for the given course and year" do
    result = Reports::FailingStudents.new("course_no" => "9900001", "year" => 2023).run

    ids = result.rows.map { |r| r[:student_id] }
    assert_includes ids, @failed.student_id      # failed (F)
    assert_not_includes ids, @passed.student_id   # passed (A)
    assert_equal "Student ID", result.columns.first[:label]
  end

  test "empty result is not an error" do
    result = Reports::FailingStudents.new("course_no" => "0000000", "year" => 2568).run
    assert result.empty?
    assert_match(/0 student/, result.summary)
  end

  private

  def make_student(id, **attrs)
    Student.create!({ student_id: id, first_name: "T", last_name: "S",
                      first_name_th: "ท", last_name_th: "ส", admission_year_be: 2567,
                      status: "active", program: programs(:cp_bachelor) }.merge(attrs))
  end
end
