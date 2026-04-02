require "test_helper"

class ProgramTest < ActiveSupport::TestCase
  test "valid program" do
    program = programs(:cp_bachelor)
    assert program.valid?
  end

  test "requires program_group" do
    program = Program.new(program_code: "9999", year_started: 2540)
    assert_not program.valid?
    assert_includes program.errors[:program_group], "must exist"
  end

  test "delegates name_en to program_group" do
    program = programs(:cp_bachelor)
    assert_equal program.program_group.name_en, program.name_en
  end

  test "delegates degree_level to program_group" do
    program = programs(:cp_bachelor)
    assert_equal "bachelor", program.degree_level
  end

  test "placeholder?" do
    assert_not programs(:cp_bachelor).placeholder?
  end
end
