require "test_helper"

class GradeStats::CohortGpaTest < ActiveSupport::TestCase
  # Isolated records (see course_distribution_test.rb for why). Cohort year
  # 2599 avoids fixture students (2565-2567 in cp_group).
  setup do
    @c3 = Course.create!(course_no: "9930001", name: "Three credits", revision_year_be: 2566, credits: 3)
    @c2 = Course.create!(course_no: "9930002", name: "Two credits", revision_year_be: 2566, credits: 2)
    @a = make_student("9900000301")
    @b = make_student("9900000302")
    @other = make_student("9900000303", admission_year_be: 2600)  # different cohort

    # Term 2022/1 — a: A(3cr) + B(2cr) → GPA 3.6; b: C+(3cr) → GPA 2.5
    grade(@a, @c3, 2022, 1, "A", 4.0)
    grade(@a, @c2, 2022, 1, "B", 3.0)
    grade(@b, @c3, 2022, 1, "C+", 2.5)
    # Term 2022/2 — a: D(2cr) → GPA 1.0; b: S only → no GPA, GPAX unchanged
    grade(@a, @c2, 2022, 2, "D", 1.0)
    grade(@b, @c2, 2022, 2, "S", nil)
    # Different cohort — must not appear anywhere
    grade(@other, @c3, 2022, 1, "F", 0.0)
  end

  test "GPA aggregates per term over the cohort only" do
    t1 = call.first

    assert_equal [ 2022, 1 ], [ t1[:year_ce], t1[:semester] ]
    assert_equal 2, t1[:gpa][:n]
    assert_in_delta 3.05, t1[:gpa][:avg], 0.001   # (3.6 + 2.5) / 2 — the F outsider excluded
    assert_in_delta 0.78, t1[:gpa][:sd], 0.001    # sample SD of [3.6, 2.5]
    assert_in_delta 2.5,  t1[:gpa][:min], 0.001
    assert_in_delta 3.6,  t1[:gpa][:max], 0.001
    assert_in_delta 3.05 - 2 * 0.78, t1[:gpa][:minus2sd], 0.01
    assert_in_delta 3.05 + 2 * 0.78, t1[:gpa][:plus2sd], 0.01
  end

  test "GPAX is cumulative; only-S/U student keeps GPAX but drops from GPA" do
    t2 = call.second

    assert_equal [ 2022, 2 ], [ t2[:year_ce], t2[:semester] ]
    assert_equal 1, t2[:gpa][:n]                  # only a has a weighted grade
    assert_in_delta 1.0, t2[:gpa][:avg], 0.001
    assert_equal 2, t2[:gpax][:n]                 # b's history still counts
    # a: (12 + 6 + 2) / 7 = 2.857…; b: unchanged 2.5 → avg 2.68
    assert_in_delta 2.68, t2[:gpax][:avg], 0.001
  end

  test "terms are chronological and empty cohorts return no terms" do
    assert_equal [ [ 2022, 1 ], [ 2022, 2 ] ], call.map { |t| [ t[:year_ce], t[:semester] ] }

    empty = GradeStats::CohortGpa.call(program_group: program_groups(:cp_group),
                                       admission_year_be: 2601)
    assert_empty empty[:terms]
  end

  private

  def call
    GradeStats::CohortGpa.call(program_group: program_groups(:cp_group),
                               admission_year_be: 2599)[:terms]
  end

  def make_student(id, admission_year_be: 2599)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: admission_year_be, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, year, semester, letter, weight)
    Grade.create!(student: student, course: course, year_ce: year, semester: semester,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
