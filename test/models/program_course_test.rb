require "test_helper"

class ProgramCourseTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert program_courses(:intro_cp).valid?
  end

  test "belongs to program and course" do
    pc = program_courses(:intro_cp)
    assert_equal programs(:cp_bachelor), pc.program
    assert_equal courses(:intro_computing), pc.course
  end

  test "same course cannot link to the same program twice" do
    dup = ProgramCourse.new(program: programs(:cp_bachelor), course: courses(:intro_computing))
    assert_not dup.valid?
    assert_includes dup.errors[:course_id], "has already been taken"
  end

  test "same course may link to a different program" do
    pc = ProgramCourse.new(program: programs(:cp_master), course: courses(:intro_computing))
    assert pc.valid?
  end
end
