require "test_helper"

class ProgramGroupTest < ActiveSupport::TestCase
  test "valid program group" do
    group = program_groups(:cp_group)
    assert group.valid?
  end

  test "requires code" do
    group = program_groups(:cp_group).dup
    group.code = nil
    assert_not group.valid?
    assert_includes group.errors[:code], "can't be blank"
  end

  test "requires unique code" do
    group = program_groups(:cp_group).dup
    assert_not group.valid?
    assert_includes group.errors[:code], "has already been taken"
  end

  test "requires name_en" do
    group = program_groups(:cp_group).dup
    group.code = "XX"
    group.name_en = nil
    assert_not group.valid?
    assert_includes group.errors[:name_en], "can't be blank"
  end

  test "requires degree_level" do
    group = program_groups(:cp_group).dup
    group.code = "XX"
    group.degree_level = nil
    assert_not group.valid?
    assert_includes group.errors[:degree_level], "can't be blank"
  end

  test "requires valid degree_level" do
    group = program_groups(:cp_group).dup
    group.code = "XX"
    group.degree_level = "invalid"
    assert_not group.valid?
    assert_includes group.errors[:degree_level], "is not included in the list"
  end

  test "has many programs" do
    group = program_groups(:cp_group)
    assert_includes group.programs, programs(:cp_bachelor)
  end

  test "has many students through programs" do
    group = program_groups(:cp_group)
    assert_respond_to group, :students
  end

  test "display_name" do
    group = program_groups(:cp_group)
    assert_equal "Computer Engineering (CP)", group.display_name
  end

  test "short_label with degree_abbr" do
    group = program_groups(:cp_group)
    assert_equal "CP — B.Eng.", group.short_label
  end

  test "short_label without degree_abbr falls back to bare code" do
    group = program_groups(:other_group)
    assert_equal "OTHER", group.short_label
  end

  test "placeholder?" do
    assert program_groups(:other_group).placeholder?
    assert_not program_groups(:cp_group).placeholder?
  end

  test "has many courses through programs" do
    group = program_groups(:cp_group)
    assert_includes group.courses, courses(:intro_computing)
  end

  # --- Cohort/generation notation (CP53 = 53rd CP generation) ---

  test "year_for_generation computes admission year from epoch" do
    group = program_groups(:cp_group)
    assert_equal 2569, group.year_for_generation(53)
  end

  test "year_for_generation returns nil for generation 0 or nil" do
    group = program_groups(:cp_group)
    assert_nil group.year_for_generation(0)
    assert_nil group.year_for_generation(nil)
  end

  test "year_for_generation returns nil when group has no epoch" do
    group = program_groups(:other_group)
    assert_nil group.year_for_generation(1)
  end

  test "generation_for_year is the inverse of year_for_generation" do
    group = program_groups(:cp_group)
    assert_equal 53, group.generation_for_year(2569)
  end

  test "generation_for_year returns nil below the epoch" do
    group = program_groups(:cp_group)
    assert_nil group.generation_for_year(2516)
  end
end
