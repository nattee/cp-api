require "test_helper"

class DissolveProgram0999Test < ActiveSupport::TestCase
  setup do
    cs_group = ProgramGroup.create!(
      code: "CS", name_en: "Computer Science", name_th: "วิทยาศาสตร์คอมพิวเตอร์",
      degree_level: "master", degree_name: "Master of Science",
      field_of_study: "Computer Engineering", first_intake_year_be: 2514
    )
    @cs_master = Program.create!(
      program_code: "0038", program_group: cs_group,
      short_name: "วท.ม. (CS)", year_started_be: 2538
    )
    @program_0999 = Program.create!(
      program_code: "0999", program_group: cs_group,
      short_name: "วท.ม. (CS)", year_started_be: 2540
    )
  end

  def create_student_on_0999(year: 2545)
    Student.create!(
      student_id: "#{year - 2500}71999921",
      first_name: "Track", last_name: "Test",
      first_name_th: "ติดตาม", last_name_th: "ทดสอบ",
      admission_year_be: year,
      program: @program_0999
    )
  end

  test "dry-run reports moves but changes nothing" do
    student = create_student_on_0999
    io = StringIO.new
    DissolveProgram0999.new(commit: false, io: io).run

    assert Program.exists?(program_code: "0999")
    assert_equal @program_0999.id, student.reload.program_id
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
