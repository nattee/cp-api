require "test_helper"

class TermContextTest < ActiveSupport::TestCase
  test "default resolves to the latest semester" do
    ctx = TermContext.default
    assert_equal 2568, ctx.academic_year_be
    assert_equal 2, ctx.semester_number   # sem_2568_2 is Semester.ordered.first
  end

  test "a stored pair is used when its year exists" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => 1 } })
    assert_equal 2567, ctx.academic_year_be
    assert_equal 1, ctx.semester_number
  end

  test "a stored whole-year value has a nil semester" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => nil } })
    assert_equal 2567, ctx.academic_year_be
    assert_nil ctx.semester_number
  end

  test "a stored year no longer in the data falls back to the default" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 1999, "semester" => 1 } })
    assert_equal 2568, ctx.academic_year_be   # default, not 1999
  end

  test "no stored value falls back to the default" do
    ctx = TermContext.from_session({})
    assert_equal 2568, ctx.academic_year_be
  end

  test "semester_record resolves the matching row" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => 2 } })
    assert_equal semesters(:sem_2567_2), ctx.semester_record
  end

  test "semester_record is nil when no row matches the pair" do
    # 2568 exists but there is no summer (semester 3) fixture for it
    ctx = TermContext.from_session({ term_context: { "year_be" => 2568, "semester" => 3 } })
    assert_nil ctx.semester_record
    assert_equal 2568, ctx.academic_year_be   # year-level use still works
  end

  test "present? is false only when there are no semesters at all" do
    assert TermContext.default.present?
  end
end
