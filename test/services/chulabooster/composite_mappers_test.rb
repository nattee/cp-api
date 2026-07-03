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
    row = { "student_id" => g.student.student_id, "course_id" => "#{g.course.revision_year_be - 543}#{g.course.course_no}",
            "academic_year" => g.year_ce, "semester_code" => "s#{g.semester}",
            "grade" => "Z", "credits_grant" => g.credits_grant }
    assert_equal key, m.cb_key(row)
    assert_equal ["grade"], m.field_diffs(g, row).map { |d| d[:field] }
  end

  # Regression for a live-run bug: a real reconcile against ChulaBooster returned matched: 0 for
  # all 31,079 local / 49,502 CB student_courses rows. Root cause was two key-encoding mismatches
  # (Grade#year_ce is CE, not BE; CB's semester_code is "s1"/"s2"/"s3", not a plain integer). These
  # tests use literal real-world-shaped values (not values mirrored from the mapper's own logic)
  # so they would have caught the bug.
  test "student_courses cb_key does not convert academic_year to BE (Grade#year_ce is CE, unlike course.revision_year_be)" do
    m = Chulabooster::Mappers::StudentCourses.new
    row = { "student_id" => "123", "course_id" => "20142110254", "academic_year" => 2018, "semester_code" => "s2" }
    assert_equal 2018, m.cb_key(row)[3] # NOT 2018 + 543 — real academic_year is already CE, matching Grade#year_ce
  end

  test "student_courses cb_key strips ChulaBooster's 's' prefix from semester_code" do
    assert_equal 1, Chulabooster::Convert.semester_number("s1")
    assert_equal 2, Chulabooster::Convert.semester_number("s2")
    assert_equal 3, Chulabooster::Convert.semester_number("s3")

    m = Chulabooster::Mappers::StudentCourses.new
    row = { "student_id" => "123", "course_id" => "20142110254", "academic_year" => 2018, "semester_code" => "s2" }
    assert_equal 2, m.cb_key(row)[4]
  end
end
