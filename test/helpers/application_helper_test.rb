require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # course_filter_tokens feeds the shared course filter: one "<program_code>-<TYPE>"
  # token per (course, program) pairing, kept coupled so program+type filter right.

  test "course_filter_tokens emits one program_code-TYPE token per pairing" do
    assert_equal "2101-C", course_filter_tokens(courses(:intro_computing))     # 2101-C
    assert_equal "2101-ELEC", course_filter_tokens(courses(:senior_project))   # 2101-ELEC
  end

  test "course_filter_tokens classifies a blank group code as OTHER" do
    # gened_cp has no course_group_code.
    assert_equal "2101-OTHER", course_filter_tokens(courses(:gened_course))
  end

  test "course_filter_tokens combines multiple programs, coupling each type" do
    ProgramCourse.create!(program: programs(:cp_master), course: courses(:intro_computing),
                          course_group_code: "2102-ELEC")
    tokens = course_filter_tokens(courses(:intro_computing).reload).split
    assert_includes tokens, "2101-C"                                    # compulsory in cp_bachelor
    assert_includes tokens, "#{programs(:cp_master).program_code}-ELEC" # elective in cp_master
  end
end
