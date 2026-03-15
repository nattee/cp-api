require "test_helper"

class GradeTest < ActiveSupport::TestCase
  test "valid grade" do
    grade = Grade.new(
      student: students(:active_student),
      course: courses(:intro_computing),
      year: 2025,
      semester: 1,
      grade: "A",
      grade_weight: 4.0,
      source: "manual"
    )
    assert grade.valid?
  end

  test "requires student" do
    grade = grades(:active_intro_computing).dup
    grade.student = nil
    assert_not grade.valid?
    assert_includes grade.errors[:student], "must exist"
  end

  test "requires course" do
    grade = grades(:active_intro_computing).dup
    grade.course = nil
    assert_not grade.valid?
    assert_includes grade.errors[:course], "must exist"
  end

  test "requires year" do
    grade = grades(:active_intro_computing).dup
    grade.year = nil
    assert_not grade.valid?
    assert_includes grade.errors[:year], "can't be blank"
  end

  test "requires semester" do
    grade = grades(:active_intro_computing).dup
    grade.semester = nil
    assert_not grade.valid?
    assert_includes grade.errors[:semester], "is not included in the list"
  end

  test "semester must be 1, 2, or 3" do
    grade = grades(:active_intro_computing).dup
    grade.semester = 4
    assert_not grade.valid?
    assert_includes grade.errors[:semester], "is not included in the list"
  end

  test "grade must be valid" do
    grade = grades(:active_intro_computing).dup
    grade.grade = "X"
    assert_not grade.valid?
    assert_includes grade.errors[:grade], "is not included in the list"
  end

  test "grade can be nil" do
    grade = grades(:active_intro_computing).dup
    grade.grade = nil
    grade.student = students(:graduated_student)
    assert grade.valid?
  end

  test "source must be imported or manual" do
    grade = grades(:active_intro_computing).dup
    grade.source = "other"
    assert_not grade.valid?
    assert_includes grade.errors[:source], "is not included in the list"
  end

  test "unique constraint on student, course, year, semester" do
    duplicate = grades(:active_intro_computing).dup
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:student_id], "is already enrolled in this course for this term"
  end

  test "same student can take same course in different semester" do
    grade = grades(:active_intro_computing).dup
    grade.semester = 2
    assert grade.valid?
  end

  test "imported? and manual?" do
    assert grades(:active_intro_computing).imported?
    assert_not grades(:active_intro_computing).manual?
    assert grades(:active_gened).manual?
    assert_not grades(:active_gened).imported?
  end

  test "grade_badge_class" do
    assert_equal "badge-grade-a", grades(:active_intro_computing).grade_badge_class
    assert_equal "badge-grade-b-plus", grades(:active_senior_project).grade_badge_class
    assert_equal "badge-grade-b", grades(:active_gened).grade_badge_class
  end

  test "graded scope excludes nil grade_weight" do
    grade = Grade.new(
      student: students(:on_leave_student),
      course: courses(:intro_computing),
      year: 2025,
      semester: 1,
      grade: "W",
      grade_weight: nil,
      source: "manual"
    )
    grade.save!
    assert_not_includes Grade.graded, grade
    assert_includes Grade.graded, grades(:active_intro_computing)
  end

  test "for_term scope" do
    results = Grade.for_term(2024, 1)
    assert_includes results, grades(:active_intro_computing)
    assert_includes results, grades(:active_gened)
    assert_not_includes results, grades(:active_senior_project)
  end
end
