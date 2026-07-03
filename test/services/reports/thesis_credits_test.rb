require "test_helper"

class Reports::ThesisCreditsTest < ActiveSupport::TestCase
  # No fixture course is a thesis course, so the only thesis grades in scope are
  # the ones built here — isolated to this test's transaction.
  setup do
    @thesis = Course.create!(course_no: "9900020", name: "Thesis Research",
                             revision_year_be: 2565, is_thesis: true)
    ProgramCourse.create!(program: programs(:cp_master), course: @thesis)
    @with    = make_student("9900000020")
    @without = make_student("9900000021")
    Grade.create!(student: @with, course: @thesis, year_ce: 2022, semester: 2,
                  grade: "A", grade_weight: 4.0, credits_grant: 12, source: "imported")
  end

  test "sums thesis-course credits and lists only students with any" do
    result = Reports::ThesisCredits.new.run

    rows_by_id = result.rows.index_by { |r| r[:student_id] }

    thesis = rows_by_id[@with.student_id]
    assert thesis, "expected the student with a thesis grade to appear"
    assert_equal 12, thesis[:thesis_credits]

    # the student with no thesis grades is absent entirely
    assert_nil rows_by_id[@without.student_id]
  end

  private

  def make_student(id, **attrs)
    Student.create!({ student_id: id, first_name: "T", last_name: "S",
                      first_name_th: "ท", last_name_th: "ส", admission_year_be: 2567,
                      status: "active", program: programs(:cp_master) }.merge(attrs))
  end
end
