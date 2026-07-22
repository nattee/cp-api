require "test_helper"

class GradeStats::CohortRankingTest < ActiveSupport::TestCase
  # Isolated cohort (pattern from cohort_gpa_test.rb): 99xxxxx ids, year 2599
  # avoids fixture students in cp_group.
  setup do
    @course = Course.create!(course_no: "9940001", name: "Ranking Course",
                             revision_year_be: 2566, credits: 3)
    @top = make_student("9900000401")
    @mid = make_student("9900000402")
    @low = make_student("9900000403")
    @unweighted = make_student("9900000404")

    grade(@top, "A", 4.0)
    grade(@mid, "B", 3.0)
    grade(@low, "C", 2.0)
    grade(@unweighted, "S", nil)
  end

  test "ranks students by GPAX descending" do
    result = call

    assert_equal [ @top.student_id, @mid.student_id, @low.student_id ], result.map { |r| r[:student_id] }
    assert_equal [ 1, 2, 3 ], result.map { |r| r[:rank] }
  end

  test "GPAX and credits are rounded" do
    top = call.first

    assert_equal 4.0, top[:gpax]
    assert_equal 3.0, top[:credits]
    assert_equal @top.display_name, top[:name]
    assert_equal @top.status, top[:status]
  end

  test "students with no weighted grades are excluded" do
    ids = call.map { |r| r[:student_id] }

    refute_includes ids, @unweighted.student_id
  end

  test "limit param caps the number of results" do
    result = GradeStats::CohortRanking.call(program_group: programs(:cp_bachelor).program_group,
                                            admission_year_be: 2599, limit: 2)

    assert_equal 2, result.size
    assert_equal [ @top.student_id, @mid.student_id ], result.map { |r| r[:student_id] }
  end

  private

  def call
    GradeStats::CohortRanking.call(program_group: programs(:cp_bachelor).program_group,
                                   admission_year_be: 2599)
  end

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, letter, weight)
    Grade.create!(student: student, course: @course, year_ce: 2022, semester: 1,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
