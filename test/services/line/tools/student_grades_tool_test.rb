require "test_helper"

class Line::Tools::StudentGradesToolTest < ActiveSupport::TestCase
  test "returns per-term record by student ID with B.E. term labels" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "6732100021" }))

    assert_equal "6732100021", result["student"]["student_id"]
    assert_equal "CP", result["student"]["program"]
    assert_equal "CP51", result["student"]["cohort"]

    # Fixture grades for active_student: 2024/1 (A intro + B gened), 2024/2 (B+ senior)
    terms = result["terms"]
    assert_equal [ "2567/1", "2567/2" ], terms.map { |t| t["term"] }
    assert_in_delta 3.5, terms[0]["gpa"], 0.001            # (4.0*3 + 3.0*3) / 6
    assert_equal %w[2103106 2110101], terms[0]["courses"].map { |c| c["course_no"] }.sort
    assert_in_delta 3.5, result["gpax"], 0.001
  end

  test "semester param filters to one term" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call(
      { "query" => "6732100021", "semester" => "2567/2" }))

    assert_equal [ "2567/2" ], result["terms"].map { |t| t["term"] }
    assert_equal [ "2110499" ], result["terms"][0]["courses"].map { |c| c["course_no"] }
  end

  test "name query matches and full-name query matches" do
    by_partial = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "ธนวัฒน์" }))
    by_full = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "ธนวัฒน์ ศรีเจริญ" }))

    assert_equal "6732100021", by_partial["student"]["student_id"]
    assert_equal "6732100021", by_full["student"]["student_id"]
  end

  test "ambiguous query returns disambiguation list" do
    # Student IDs starting "6" match several fixture students by prefix... use
    # a shared name instead: create a second student sharing a name fragment.
    Student.create!(student_id: "9900000901", first_name: "Thanawat", last_name: "Other",
                    first_name_th: "ธนวัฒน์", last_name_th: "อื่น",
                    admission_year_be: 2567, status: "active", program: programs(:cp_bachelor))

    result = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "ธนวัฒน์" }))

    assert_match(/Multiple students/, result["error"])
    assert_equal 2, result["matches"].size
    assert result["matches"].all? { |m| m["student_id"].present? }
  end

  test "unknown student returns error" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "0000000000" }))
    assert_match(/No student found/, result["error"])
  end

  test "bad semester format returns error" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call(
      { "query" => "6732100021", "semester" => "first term" }))
    assert_match(/Could not parse semester/, result["error"])
  end

  test "student cohort is nil when the program group has no epoch" do
    Student.create!(student_id: "9900001101", first_name: "No", last_name: "Epoch",
                    first_name_th: "ไม่มี", last_name_th: "รุ่น",
                    admission_year_be: 2560, status: "active", program: Program.placeholder)

    result = JSON.parse(Line::Tools::StudentGradesTool.call({ "query" => "9900001101" }))

    assert result["student"].key?("cohort")
    assert_nil result["student"]["cohort"]
  end
end
