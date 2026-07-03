require "test_helper"

class Reports::GroupCreditShortfallTest < ActiveSupport::TestCase
  # Unique course_group ("TestCore") so only the students built here carry credits
  # in it; isolated records keep the locked fixture counts untouched.
  setup do
    @c1 = Course.create!(course_no: "9900010", name: "Core A", revision_year_be: 2565,
                         course_group: "TestCore")
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @c1)
    @c2 = Course.create!(course_no: "9900011", name: "Core B", revision_year_be: 2565,
                         course_group: "TestCore")
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @c2)
    @below = make_student("9900000010", admission_year_be: 2566)
    @above = make_student("9900000011", admission_year_be: 2567)
    # @above earns 6 Core credits (two passing courses); @below earns none.
    Grade.create!(student: @above, course: @c1, year_ce: 2023, semester: 1,
                  grade: "A", grade_weight: 4.0, credits_grant: 3, source: "imported")
    Grade.create!(student: @above, course: @c2, year_ce: 2023, semester: 2,
                  grade: "A", grade_weight: 4.0, credits_grant: 3, source: "imported")
  end

  test "lists only students below the credit threshold, with the right gap" do
    result = Reports::GroupCreditShortfall.new(
      "course_group" => "TestCore", "required_credits" => 6
    ).run

    rows_by_id = result.rows.index_by { |r| r[:student_id] }

    shortfall = rows_by_id[@below.student_id]
    assert shortfall, "expected @below in the shortfall list"
    assert_equal 0, shortfall[:earned]
    assert_equal 6, shortfall[:required]
    assert_equal 6, shortfall[:missing]

    # @above earned 6 → at threshold, excluded
    assert_nil rows_by_id[@above.student_id]
  end

  test "respects the admission-year cohort filter" do
    result = Reports::GroupCreditShortfall.new(
      "course_group" => "TestCore", "required_credits" => 6, "admission_year" => 2566
    ).run

    ids = result.rows.map { |r| r[:student_id] }
    assert_includes ids, @below.student_id       # admission 2566 → in cohort, below threshold
    assert_not_includes ids, @above.student_id   # admission 2567 → filtered out by cohort
  end

  private

  def make_student(id, **attrs)
    Student.create!({ student_id: id, first_name: "T", last_name: "S",
                      first_name_th: "ท", last_name_th: "ส", admission_year_be: 2567,
                      status: "active", program: programs(:cp_bachelor) }.merge(attrs))
  end
end
