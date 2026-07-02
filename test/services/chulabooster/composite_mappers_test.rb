require "test_helper"

class Chulabooster::CompositeMappersTest < ActiveSupport::TestCase
  test "parse_course_id splits CE year and course_no with CE->BE" do
    assert_equal ["2110254", 2557], Chulabooster::Convert.parse_course_id("20142110254")
  end

  test "program_courses mapper matches on (program_code, course_no, revision_be)" do
    m = Chulabooster::Mappers::ProgramCourses.new
    pc = ProgramCourse.joins(:program, :course).first
    key = m.local_key(pc)
    assert_equal 3, key.length
    row = { "program_id" => key[0], "course_no" => key[1],
            "course_id" => "#{key[2] - 543}#{key[1]}" }
    assert_equal key, m.cb_key(row)
    assert_empty m.field_diffs(pc, row)  # membership-only: matched == identical
  end

  test "student_courses mapper builds a 5-part key and compares grade" do
    m = Chulabooster::Mappers::StudentCourses.new
    g = Grade.includes(:student, :course).where.not(grade: [nil, ""]).first
    key = m.local_key(g)
    assert_equal 5, key.length
    row = { "student_id" => key[0], "course_id" => "#{key[2] - 543}#{key[1]}",
            "academic_year" => key[3] - 543, "semester_code" => g.semester.to_s,
            "grade" => "Z", "credits_grant" => g.credits_grant }
    assert_equal key, m.cb_key(row)
    assert_equal ["grade"], m.field_diffs(g, row).map { |d| d[:field] }
  end
end
