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

  test "group_label maps known codes via the constant" do
    assert_equal "Compulsory", ProgramCourse.group_label("4784-C")
  end

  test "group_label falls back to the raw suffix for unknown codes" do
    assert_equal "NEWGRP", ProgramCourse.group_label("9999-NEWGRP")
  end

  test "group_label handles blank" do
    assert_equal ProgramCourse::UNGROUPED_LABEL, ProgramCourse.group_label(nil)
    assert_equal ProgramCourse::UNGROUPED_LABEL, ProgramCourse.group_label("")
  end

  test "group_sort_key orders: constant order, unknown alphabetical, blank last" do
    codes = [nil, "9999-B", "4784-ELEC", "9999-A", "4784-C"]
    sorted = codes.sort_by { |c| ProgramCourse.group_sort_key(c) }
    assert_equal ["4784-C", "4784-ELEC", "9999-A", "9999-B", nil], sorted
  end

  test "filter_type classifies by suffix, independent of the prefix" do
    # "-C" => compulsory, regardless of whether the prefix is the program_code.
    assert_equal "C", ProgramCourse.filter_type("4784-C")
    assert_equal "C", ProgramCourse.filter_type("2101-C")
    # "-ELEC" and "-ELEC2" both collapse to ELEC.
    assert_equal "ELEC", ProgramCourse.filter_type("4784-ELEC")
    assert_equal "ELEC", ProgramCourse.filter_type("3736-ELEC2")
    # Any other suffix, and blank, are OTHER.
    assert_equal "OTHER", ProgramCourse.filter_type("4784-MS")
    assert_equal "OTHER", ProgramCourse.filter_type(nil)
    assert_equal "OTHER", ProgramCourse.filter_type("")
  end
end
