require "test_helper"

class ProgramTest < ActiveSupport::TestCase
  test "valid program" do
    program = programs(:cp_bachelor)
    assert program.valid?
  end

  test "requires program_group" do
    program = Program.new(program_code: "9999", year_started_be: 2540)
    assert_not program.valid?
    assert_includes program.errors[:program_group], "must exist"
  end

  test "delegates name_en to program_group" do
    program = programs(:cp_bachelor)
    assert_equal program.program_group.name_en, program.name_en
  end

  test "delegates degree_level to program_group" do
    program = programs(:cp_bachelor)
    assert_equal "bachelor", program.degree_level
  end

  test "placeholder?" do
    assert_not programs(:cp_bachelor).placeholder?
  end

  test "courses through program_courses" do
    assert_includes programs(:cp_bachelor).courses, courses(:intro_computing)
  end

  test "destroying a program destroys its join rows but keeps the courses" do
    program = Program.create!(program_code: "8888", program_group: program_groups(:cp_group), year_started_be: 2560)
    program.program_courses.create!(course: courses(:senior_project))
    assert_difference "ProgramCourse.count", -1 do
      assert_no_difference "Course.count" do
        program.destroy!
      end
    end
    assert Course.exists?(courses(:senior_project).id)
  end
end
