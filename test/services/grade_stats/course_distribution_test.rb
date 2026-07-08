require "test_helper"

class GradeStats::CourseDistributionTest < ActiveSupport::TestCase
  # Isolated records, not fixtures: the LINE lookup-tool tests assert exact
  # fixture counts, so stats data lives only inside this test's transaction.
  setup do
    @old = Course.create!(course_no: "9910327", name: "Algo (old rev)", revision_year_be: 2560, credits: 3)
    @new = Course.create!(course_no: "9910327", name: "Algo (new rev)", revision_year_be: 2566, credits: 3)
    @s1, @s2, @s3, @s4 = (1..4).map { |i| make_student("99000001#{i.to_s.rjust(2, '0')}") }
    grade(@s1, @old, "A", 4.0)
    grade(@s2, @new, "A", 4.0)
    grade(@s3, @new, "B+", 3.5)
    grade(@s4, @new, "S", nil)   # counted in the distribution, excluded from GPA
  end

  test "combines all revisions of a course_no, counts ordered by GRADES" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 2)

    assert_equal({ "A" => 2, "B+" => 1, "S" => 1 }, r[:counts])
    assert_equal %w[A B+ S], r[:counts].keys
    assert_equal 4, r[:total]
  end

  test "GPA covers weighted grades only, sample SD, 2 decimals" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 2)

    assert_equal 3, r[:gpa][:n]                 # the S row is excluded
    assert_in_delta 3.83, r[:gpa][:mean], 0.001 # (4 + 4 + 3.5) / 3
    assert_in_delta 0.29, r[:gpa][:sd], 0.001   # sample SD of [4, 4, 3.5]
  end

  test "nil semester returns one result per term of the year, in order" do
    grade(@s1, @new, "B", 3.0, semester: 1)

    results = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025)

    assert_equal [ 1, 2 ], results.map { |r| r[:semester] }
    assert_equal({ "B" => 1 }, results.first[:counts])
  end

  test "term with no grades returns an empty distribution" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 3)

    assert_equal 0, r[:total]
    assert_empty r[:counts]
    assert_equal({ n: 0, mean: nil, sd: nil }, r[:gpa])
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, letter, weight, semester: 2)
    Grade.create!(student: student, course: course, year_ce: 2025, semester: semester,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
