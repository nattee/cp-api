require "test_helper"

class Line::Tools::SemesterOverviewToolTest < ActiveSupport::TestCase
  # Fixtures: sem_2568_1 has 2 offerings (2110101 confirmed ×2 sections,
  # 2110499 planned ×1 section); sem_2567_1 has 2 offerings (2110101 ×2
  # sections, 2103106 ×1 section).

  test "explicit semester returns counts and per-program breakdown" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2568/1" }))

    assert_equal "2568/1", result["semester"]
    assert_equal 2, result["offerings"]
    assert_equal 3, result["sections"]
    assert_equal 2, result["distinct_courses"]
    assert result["by_program"].is_a?(Array)
    assert result["by_program"].all? { |row| row["program"].present? && row["offerings"].positive? }
  end

  test "omitted semester defaults to the latest" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({}))
    assert_equal Semester.ordered.first.display_name, result["semester"]
  end

  test "unknown semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2500/1" }))
    assert_match(/No semester 2500\/1/, result["error"])
  end

  test "unparseable semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "next term" }))
    assert_match(/Could not parse semester/, result["error"])
  end

  test "by_program does not double-count a course pairing fan-out within the same program group" do
    # program_courses is many-to-many: intro_computing is already paired to
    # cp_bachelor (fixture intro_cp). Pair it to a SECOND program in the SAME
    # group (CP) too -- this mirrors production, where a course row is paired
    # to multiple revisions of one program group. A plain grouped .count over
    # the join would count the intro_computing offering twice under "CP".
    second_cp_program = Program.create!(
      program_code: "9901",
      program_group: program_groups(:cp_group),
      year_started_be: 2560
    )
    ProgramCourse.create!(program: second_cp_program, course: courses(:intro_computing))

    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2568/1" }))
    cp_row = result["by_program"].find { |row| row["program"] == "CP" }

    # sem_2568_1 has exactly 2 offerings (intro_computing, senior_project),
    # both paired only to CP-group programs -- so CP's offering count must
    # stay 2, not inflate to 3 from the extra pairing.
    assert_equal 2, cp_row["offerings"]
    assert_equal result["offerings"], result["by_program"].sum { |row| row["offerings"] }
  end

  test "by_program surfaces an unlinked row for offerings whose course has no program pairing" do
    # sem_2568_1's fixture offerings (intro_computing, senior_project) are both
    # paired via program_courses fixtures (intro_cp, senior_cp) -- so add an
    # unpaired course/offering here rather than editing fixtures, to exercise
    # the gap-reconciliation logic without disturbing other tests.
    orphan_course = Course.create!(
      name: "Orphan Elective", course_no: "9999901", revision_year_be: 2565,
      is_gened: false, credits: 3, l_credits: 3, nl_credits: 0,
      l_hours: 3, nl_hours: 0, s_hours: 6, is_thesis: false
    )
    CourseOffering.create!(course: orphan_course, semester: semesters(:sem_2568_1), status: "confirmed")

    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({ "semester" => "2568/1" }))

    assert_equal 3, result["offerings"]
    assert_equal({ "program" => "unlinked", "offerings" => 1 }, result["by_program"].last)
    assert_equal result["offerings"], result["by_program"].sum { |row| row["offerings"] }
  end
end
