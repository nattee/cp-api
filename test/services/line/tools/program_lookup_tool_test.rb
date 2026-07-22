require "test_helper"

class Line::Tools::ProgramLookupToolTest < ActiveSupport::TestCase
  # Fixtures: cp_group (CP, bachelor, first intake 2517) has one revision
  # ("2101"/2540) holding 3 students (active / graduated / on_leave);
  # cm_group (CM, master) has one revision and no students; other_group
  # (OTHER) is a bookkeeping placeholder with degree_name "Unknown".

  test "lists real groups ordered by degree level, excluding placeholder groups" do
    result = JSON.parse(Line::Tools::ProgramLookupTool.call({}))

    assert_equal %w[CP CM], result["programs"].map { |p| p["code"] }
    assert_match(/current enrollment/, result["note"])
  end

  test "group payload carries names, degree, epoch, and nested revisions" do
    cp = JSON.parse(Line::Tools::ProgramLookupTool.call({}))["programs"].first

    assert_equal "Computer Engineering", cp["name_en"]
    assert_equal "วิศวกรรมคอมพิวเตอร์", cp["name_th"]
    assert_equal "bachelor", cp["degree_level"]
    assert_match(/B\.Eng\./, cp["degree"])
    assert_equal 2517, cp["first_intake_year_be"]
    assert_equal [
      { "year_started_be" => 2540, "program_code" => "2101",
        "total_credit" => nil, "active" => true, "students" => 3 }
    ], cp["revisions"]
  end

  test "counts distinguish current enrollment from the all-time total" do
    cp = JSON.parse(Line::Tools::ProgramLookupTool.call({}))["programs"].first

    assert_equal 3, cp["students_total"]
    assert_equal 1, cp["students_active"]
  end

  test "program_code filter is case-insensitive" do
    result = JSON.parse(Line::Tools::ProgramLookupTool.call({ "program_code" => "cm" }))

    assert_equal %w[CM], result["programs"].map { |p| p["code"] }
  end

  test "unknown program code returns error listing known codes" do
    result = JSON.parse(Line::Tools::ProgramLookupTool.call({ "program_code" => "XX" }))

    assert_match(/Unknown program code XX/, result["error"])
    assert_equal %w[CM CP], result["known_codes"]
  end

  test "degree_level filter" do
    result = JSON.parse(Line::Tools::ProgramLookupTool.call({ "degree_level" => "master" }))

    assert_equal %w[CM], result["programs"].map { |p| p["code"] }
  end

  test "counts aggregate across revisions, sorted by year started" do
    second_revision = Program.create!(
      program_code: "9901", program_group: program_groups(:cp_group),
      year_started_be: 2560, active: false
    )
    Student.create!(
      student_id: "6832100010", first_name: "Extra", last_name: "Student",
      first_name_th: "เอ็กซ์ตร้า", last_name_th: "สติวเดนท์",
      admission_year_be: 2568, status: "active", program: second_revision
    )

    cp = JSON.parse(Line::Tools::ProgramLookupTool.call({ "program_code" => "CP" }))["programs"].first

    assert_equal [ 2540, 2560 ], cp["revisions"].map { |r| r["year_started_be"] }
    assert_equal [ 3, 1 ], cp["revisions"].map { |r| r["students"] }
    assert_equal [ true, false ], cp["revisions"].map { |r| r["active"] }
    assert_equal 4, cp["students_total"]
    assert_equal 2, cp["students_active"]
  end
end
