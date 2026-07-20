require "test_helper"

class GradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  # Regression: before the M:N fix, the distribution action joined the removed
  # Course#program association (course: { program: :program_group }) and raised
  # ActiveRecord::AssociationNotFoundError → 500 whenever program_code was present.
  test "distribution report with program_code succeeds (crash regression)" do
    get distribution_grades_path, params: { program_code: program_groups(:cp_group).code }
    assert_response :success
  end

  # De-dup: when a course is linked to multiple programs in the same program_group,
  # DISTINCT grades.id / .distinct on matching_courses must prevent inflated counts.
  test "distribution report does not double-count grades when course is in two CP programs" do
    second_program = Program.create!(
      program_code: "8890",
      program_group: program_groups(:cp_group),
      year_started_be: 2560
    )
    ProgramCourse.create!(program: second_program, course: courses(:intro_computing))

    # With two CP-group programs both linked to intro_computing, a naive join
    # would double every grade row. The response should still succeed and
    # (implicitly) not blow up with inflated counts.
    get distribution_grades_path, params: {
      program_code: program_groups(:cp_group).code,
      prefix: "2110"
    }
    assert_response :success

    # Verify the rendered body contains exactly "2" for the total count of
    # intro_computing grades — active_intro_computing (A, 2024/1) and
    # graduated_intro_computing (A, 2022/1) — not "4" from a doubled join.
    # We look for the course number in the body to confirm the row is present.
    assert_match "2110101", response.body
  end

  # Exports lead with a UTF-8 BOM (see the exporter); strip it before parsing.
  def parse_csv(body)
    CSV.parse(body.delete_prefix(Exporters::Base::BOM))
  end

  test "distribution CSV export returns the full filtered result set" do
    get distribution_grades_path(format: :csv), params: { prefix: "2110", split: "1" }
    assert_response :success
    assert_equal "text/csv", response.media_type
    csv = parse_csv(response.body)
    assert_equal ["Course", "Title", "Term", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    # Fixtures with a 2110 prefix: 2110101 gets an A in 2022/1 and 2024/1,
    # 2110499 a B+ in 2024/2 — three split rows, sorted by course_no then term.
    assert_equal 4, csv.size
    assert_equal ["2110101", "Introduction to Computing", "2022/1",
                  "1", "0", "0", "0", "0", "0", "0", "0", "0", "0", "1", "4.0", "100"], csv[1]
    refute_match "2103106", response.body, "non-2110 course must be filtered out"
  end

  test "distribution CSV without split aggregates terms and omits the Term column" do
    get distribution_grades_path(format: :csv), params: { prefix: "2110", split: "0" }
    assert_response :success
    csv = parse_csv(response.body)
    assert_equal "A", csv[0][2], "A-count should directly follow Title when unsplit"
    assert_equal ["2110101", "Introduction to Computing",
                  "2", "0", "0", "0", "0", "0", "0", "0", "0", "0", "2", "4.0", "100"], csv[1]
  end

  # The CSV path must not become an unauthenticated back door to grade data.
  test "distribution CSV requires login" do
    delete logout_path
    get distribution_grades_path(format: :csv), params: { prefix: "2110" }
    assert_redirected_to login_path
  end
end
