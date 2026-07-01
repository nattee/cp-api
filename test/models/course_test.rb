require "test_helper"

class CourseTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid course" do
    course = Course.new(name: "Test Course", course_no: "9999999", revision_year: 2565)
    assert course.valid?
  end

  test "requires name" do
    course = courses(:intro_computing).dup
    course.course_no = "0000001"
    course.name = nil
    assert_not course.valid?
    assert_includes course.errors[:name], "can't be blank"
  end

  test "requires course_no" do
    course = courses(:intro_computing).dup
    course.course_no = nil
    assert_not course.valid?
    assert_includes course.errors[:course_no], "can't be blank"
  end

  test "requires revision_year" do
    course = courses(:intro_computing).dup
    course.course_no = "0000002"
    course.revision_year = nil
    assert_not course.valid?
    assert_includes course.errors[:revision_year], "can't be blank"
  end

  test "revision_year must be integer" do
    course = courses(:intro_computing).dup
    course.course_no = "0000003"
    course.revision_year = 25.5
    assert_not course.valid?
    assert_includes course.errors[:revision_year], "must be an integer"
  end

  test "course_no must be unique within revision_year" do
    course = Course.new(
      name: "Duplicate",
      course_no: courses(:intro_computing).course_no,
      revision_year: courses(:intro_computing).revision_year
    )
    assert_not course.valid?
    assert_includes course.errors[:course_no], "already exists for this revision year"
  end

  test "same course_no allowed with different revision_year" do
    course = Course.new(
      name: "Same No Different Year",
      course_no: courses(:intro_computing).course_no,
      revision_year: courses(:intro_computing).revision_year + 5
    )
    assert course.valid?
  end

  test "credits must be integer" do
    course = courses(:intro_computing).dup
    course.course_no = "0000004"
    course.credits = 1.5
    assert_not course.valid?
    assert_includes course.errors[:credits], "must be an integer"
  end

  test "credits allows nil" do
    course = Course.new(name: "No Credits", course_no: "0000005", revision_year: 2565, credits: nil)
    assert course.valid?
  end

  # --- Associations ---

  test "has many programs through program_courses" do
    course = courses(:intro_computing)
    assert_includes course.programs, programs(:cp_bachelor)
  end

  test "valid without any program" do
    course = Course.new(name: "No Program", course_no: "0000006", revision_year: 2565)
    assert course.valid?
  end

  # --- Many-to-many behavior ---

  test "course can belong to multiple programs" do
    course = courses(:intro_computing)
    course.programs << programs(:cp_master)
    assert_equal 2, course.reload.programs.count
    assert_includes course.programs, programs(:cp_bachelor)
    assert_includes course.programs, programs(:cp_master)
  end

  test "import_program links a program after save" do
    course = Course.new(name: "Linked", course_no: "0000007", revision_year: 2565,
                        import_program: programs(:cp_bachelor))
    assert_difference "ProgramCourse.count", 1 do
      course.save!
    end
    assert_includes course.programs, programs(:cp_bachelor)
  end
end
