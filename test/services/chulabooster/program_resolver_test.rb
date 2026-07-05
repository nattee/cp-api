require "test_helper"

class Chulabooster::ProgramResolverTest < ActiveSupport::TestCase
  # Build isolated groups/programs inline (fixtures carry only CP/CM/OTHER) — the
  # resolver loads the whole Program table, so tests must control what exists.
  # Fixture programs in play: cp_bachelor (CP, 2540), cp_master (CM, 2545).
  setup do
    @cs   = make_group("CS",   "Computer Science",     "master")
    @se   = make_group("SE",   "Software Engineering", "master")
    @cedt = make_group("CEDT", "Comp Eng and Digital Technology", "bachelor")
    @cd   = make_group("CD",   "Computer Engineering", "doctoral")

    @cs_old  = make_program(@cs, "9101", 2524)
    @cs_new  = make_program(@cs, "9102", 2561)
    @cm_old  = make_program(program_groups(:cm_group), "9201", 2535)
    @cd_1998 = make_program(@cd, "9301", 2541)
    @cedt_1  = make_program(@cedt, "9401", 2566)

    # SE twins at 2558: majority enrollment sits on the HIGHER code — proves the
    # default is majority, not lower-code.
    @se_twin_lo = make_program(@se, "9501", 2558)
    @se_twin_hi = make_program(@se, "9502", 2558)
    2.times { |i| make_student("990000000#{i}", @se_twin_hi) }
    make_student("9900000002", @se_twin_lo)

    # CD twins at 2552 with ZERO enrollment: lower code is the tiebreak.
    @cd_twin_lo = make_program(@cd, "9302", 2552)
    @cd_twin_hi = make_program(@cd, "9303", 2552)

    @resolver = Chulabooster::ProgramResolver.new
  end

  test "direct major resolves to the latest revision at or before admission" do
    r = @resolver.resolve(major_code: "21101", student_id: "6470000021", admission_year_be: 2567)
    assert_equal @cs_new, r.program
    assert_equal "CS", r.group
    assert_nil r.failure
    refute r.heuristic
    assert_empty r.flags

    r_old = @resolver.resolve(major_code: "21101", student_id: "3070000021", admission_year_be: 2530)
    assert_equal @cs_old, r_old.program
  end

  test "unmapped major code fails cleanly" do
    r = @resolver.resolve(major_code: "21103", student_id: "4931802021", admission_year_be: 2549)
    assert_match(/unmapped major_code/, r.failure)
    assert_nil r.program
  end

  test "direct major with no old-enough program fails cleanly (no fallback for direct majors)" do
    r = @resolver.resolve(major_code: "21104", student_id: "6033000021", admission_year_be: 2560)
    assert_match(/no CEDT program/, r.failure)
  end

  test "21100 segment 70 resolves to CM with a heuristic flag" do
    r = @resolver.resolve(major_code: "21100", student_id: "6070106021", admission_year_be: 2567)
    assert_equal "CM", r.group
    assert_equal programs(:cp_master), r.program
    assert r.heuristic
    assert r.flags.any? { |f| f.include?("inferred from student_id pattern") }
  end

  test "21100 segment 71 resolves to CD when a CD program exists by then" do
    r = @resolver.resolve(major_code: "21100", student_id: "5971407721", admission_year_be: 2557)
    assert_equal "CD", r.group
    assert_equal @cd_twin_lo, r.program # 2552 twins, both empty -> lower code
    assert r.twin_tie
  end

  test "21100 segment 71 before CD existed falls back to CM, not CP" do
    # The two manually-confirmed 1996 students (3971081121/3971235521) depend on
    # FALLBACK_ORDER trying the other graduate group before bachelor.
    r = @resolver.resolve(major_code: "21100", student_id: "3971081121", admission_year_be: 2539)
    assert_equal "CM", r.group
    assert_equal @cm_old, r.program
    assert r.flags.any? { |f| f.include?("reassigned to CM") }
  end

  test "21100 with a 7-digit legacy id defaults to CP with a flag" do
    r = @resolver.resolve(major_code: "21100", student_id: "4012345", admission_year_be: 2567)
    assert_equal "CP", r.group
    assert_equal programs(:cp_bachelor), r.program
    assert r.heuristic
    assert r.flags.any? { |f| f.include?("legacy 7-digit student_id") }
  end

  test "21100 bachelor-range segment resolves to CP without twin noise" do
    r = @resolver.resolve(major_code: "21100", student_id: "6732100021", admission_year_be: 2567)
    assert_equal "CP", r.group
    refute r.twin_tie
  end

  test "twin tie picks majority enrollment, not lower program_code" do
    r = @resolver.resolve(major_code: "21102", student_id: "6070000021", admission_year_be: 2560)
    assert_equal @se_twin_hi, r.program, "must pick the 2-student twin over the 1-student lower code"
    assert r.twin_tie
    assert r.flags.any? { |f| f.include?("majority enrollment") }
  end

  private

  def make_group(code, name_en, degree_level)
    ProgramGroup.create!(code: code, name_en: name_en, degree_level: degree_level,
                         degree_name: "Test Degree", field_of_study: "Computer Engineering")
  end

  def make_program(group, program_code, year_started_be)
    Program.create!(program_group: group, program_code: program_code,
                    year_started_be: year_started_be, short_name: "T")
  end

  def make_student(student_id, program)
    Student.create!(student_id: student_id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส", admission_year_be: program.year_started_be,
                    status: "active", program: program)
  end
end
