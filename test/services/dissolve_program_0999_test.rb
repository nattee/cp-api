require "test_helper"

class DissolveProgram0999Test < ActiveSupport::TestCase
  def create_student_on_0999(year: 2545)
    Student.create!(
      student_id: "#{year - 2500}71999921",
      first_name: "Track", last_name: "Test",
      first_name_th: "ติดตาม", last_name_th: "ทดสอบ",
      admission_year_be: year,
      program: programs(:cs_master_0999)
    )
  end

  test "dry-run reports moves but changes nothing" do
    student = create_student_on_0999
    io = StringIO.new
    DissolveProgram0999.new(commit: false, io: io).run

    assert Program.exists?(program_code: "0999")
    assert_equal programs(:cs_master_0999).id, student.reload.program_id
    assert_match(/DRY-RUN/, io.string)
    assert_match(/2545 -> 0038: 1/, io.string)
  end

  test "commit moves students to the latest regular revision at or before their admission year and deletes 0999" do
    student = create_student_on_0999(year: 2545)
    DissolveProgram0999.new(commit: true, io: StringIO.new).run

    assert_equal "0038", student.reload.program.program_code
    assert_not Program.exists?(program_code: "0999")
  end

  test "raises when a student has no replacement revision" do
    create_student_on_0999(year: 2530) # predates 0038 (2538) and any other CS fixture row
    assert_raises(RuntimeError) do
      DissolveProgram0999.new(commit: false, io: StringIO.new).run
    end
  end
end
