require "test_helper"

class Chulabooster::MappersTest < ActiveSupport::TestCase
  test "ce_to_be converts CE and leaves BE" do
    assert_equal 2557, Chulabooster::Convert.ce_to_be(2014)
    assert_equal 2565, Chulabooster::Convert.ce_to_be(2565)
    assert_nil Chulabooster::Convert.ce_to_be(nil)
  end

  test "programs mapper keys and diffs" do
    m = Chulabooster::Mappers::Programs.new
    p = programs(:cp_bachelor)   # program_code "2101"
    assert_equal "2101", m.local_key(p)
    assert_equal "2101", m.cb_key({ "program_id" => "2101" })

    identical = { "program_id" => "2101", "program_name" => p.name_en, "program_name_alt" => p.name_th,
                  "revision_year" => p.year_started_be - 543, "program_code" => p.alternative_program_code }
    assert_empty m.field_diffs(p, identical)

    changed = identical.merge("program_name" => "Different Name")
    diffs = m.field_diffs(p, changed)
    assert_equal ["name_en"], diffs.map { |d| d[:field] }
  end

  test "courses mapper key uses CE->BE revision and detects a changed field" do
    m = Chulabooster::Mappers::Courses.new
    c = courses(:intro_computing)  # course_no "2110101", revision_year_be 2565
    assert_equal ["2110101", 2565], m.local_key(c)
    assert_equal ["2110101", 2565], m.cb_key({ "course_no" => "2110101", "revision_year" => 2022 }) # 2022+543
    row = { "course_name" => c.name, "course_name_alt" => c.name_th, "credits" => 99,
            "l_credits" => c.l_credits, "l_hours" => c.l_hours, "nl_hours" => c.nl_hours,
            "s_hours" => c.s_hours, "is_thesis" => c.is_thesis, "gened" => c.is_gened }
    assert_equal ["credits"], m.field_diffs(c, row).map { |d| d[:field] }
  end

  test "students mapper flags status as encoding-unverified" do
    m = Chulabooster::Mappers::Students.new
    s = students(:active_student)
    row = { "student_id" => s.student_id, "firstname" => s.first_name, "lastname" => s.last_name,
            "firstname_alt" => s.first_name_th, "lastname_alt" => s.last_name_th, "gender" => s.sex,
            "start_academic_year" => s.admission_year_be - 543, "student_status" => "9" }
    diffs = m.field_diffs(s, row)
    status = diffs.find { |d| d[:field] == "status" }
    assert status && status[:verified] == false
  end
end
