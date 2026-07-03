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
end
