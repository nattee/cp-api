require "test_helper"

class SemesterTest < ActiveSupport::TestCase
  test "valid with year_be and semester_number" do
    semester = Semester.new(year_be: 2567, semester_number: 1)
    assert semester.valid?
  end

  test "requires year_be" do
    semester = semesters(:sem_2568_1).dup
    semester.year_be = nil
    assert_not semester.valid?
    assert_includes semester.errors[:year_be], "can't be blank"
  end

  test "requires semester_number" do
    semester = Semester.new(year_be: 2567, semester_number: nil)
    assert_not semester.valid?
    assert_includes semester.errors[:semester_number], "can't be blank"
  end

  test "semester_number must be 1, 2, or 3" do
    semester = Semester.new(year_be: 2567, semester_number: 4)
    assert_not semester.valid?
    assert_includes semester.errors[:semester_number], "is not included in the list"
  end

  test "unique on year_be and semester_number" do
    semester = Semester.new(
      year_be: semesters(:sem_2568_1).year_be,
      semester_number: semesters(:sem_2568_1).semester_number
    )
    assert_not semester.valid?
    assert_includes semester.errors[:year_be], "has already been taken"
  end

  test "display_name returns year/semester" do
    semester = semesters(:sem_2568_1)
    assert_equal "2568/1", semester.display_name
  end

  test "ordered scope sorts desc by year then semester" do
    ordered = Semester.ordered.to_a
    assert_operator ordered.index(semesters(:sem_2568_2)), :<, ordered.index(semesters(:sem_2568_1))
  end
end
