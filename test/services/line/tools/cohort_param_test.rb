require "test_helper"

class Line::Tools::CohortParamTest < ActiveSupport::TestCase
  test "resolves by B.E. admission year" do
    result = Line::Tools::CohortParam.resolve(program_code: "CP", admission_year: 2599)

    assert_equal program_groups(:cp_group), result[:group]
    assert_equal 2599, result[:admission_year_be]
  end

  test "resolves by C.E. admission year (+543)" do
    result = Line::Tools::CohortParam.resolve(program_code: "cp", admission_year: 2056)

    assert_equal program_groups(:cp_group), result[:group]
    assert_equal 2599, result[:admission_year_be]
  end

  test "resolves by generation via the group's first_intake_year_be epoch" do
    # cp_group fixture: first_intake_year_be 2517. Generation 51 -> 2517 + 51 - 1 = 2567.
    result = Line::Tools::CohortParam.resolve(program_code: "CP", generation: 51)

    assert_equal program_groups(:cp_group), result[:group]
    assert_equal 2567, result[:admission_year_be]
  end

  test "blank program_code returns an error" do
    result = Line::Tools::CohortParam.resolve(program_code: "")

    assert_equal "program_code is required", result[:error]
  end

  test "unknown program_code returns an error listing valid codes" do
    result = Line::Tools::CohortParam.resolve(program_code: "ZZ", admission_year: 2599)

    assert_match(/Unknown program code ZZ/, result[:error])
    assert_match(/CP/, result[:error])
  end

  test "generation for a group without a recorded epoch returns an error" do
    result = Line::Tools::CohortParam.resolve(program_code: program_groups(:other_group).code, generation: 1)

    assert_match(/no recorded first intake year/, result[:error])
  end

  test "neither admission_year nor generation returns an error" do
    result = Line::Tools::CohortParam.resolve(program_code: "CP")

    assert_equal "admission_year or generation is required", result[:error]
  end
end
