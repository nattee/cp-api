# test/services/book30/importer_test.rb
require "test_helper"

class Book30ImporterTest < ActiveSupport::TestCase
  def line_xml(x0, y0, text)
    chars = text.each_char.map { |c| %(<char quad="0 0 0 0" x="0" y="0" c="#{CGI.escapeHTML(c)}"/>) }.join
    %(<line bbox="#{x0} #{y0} 100 10" wmode="0" dir="1 0"><font name="F" size="9">#{chars}</font></line>)
  end

  setup do
    @cs = ProgramGroup.create!(code: "CS", name_en: "Computer Science", degree_level: "master",
                               degree_name: "Master of Science", field_of_study: "Computer Engineering", first_intake_year_be: 2514)
    @cs_old = Program.create!(program_code: "1027", program_group: @cs, year_started_be: 2524)
    @cs_new = Program.create!(program_code: "0038", program_group: @cs, year_started_be: 2538)
    @ce = ProgramGroup.create!(code: "CE", name_en: "Computer Science Certificate", degree_level: "certificate",
                               degree_name: "Certificate in Computer Science", field_of_study: "Computer Science", first_intake_year_be: 2512)
    @ce_prog = Program.create!(program_code: "CE2512", program_group: @ce, year_started_be: 2512, active: false)
    @cm = program_groups(:cm_group)
    @cm_first = Program.create!(program_code: "0037", program_group: @cm, year_started_be: 2535)
    @cp_0018 = Program.create!(program_code: "0018", program_group: program_groups(:cp_group), year_started_be: 2519)
    # existing CS student to be matched, and a misfiled first-cohort CM student
    @existing = Student.create!(student_id: "3670100021", first_name: "Somchai", last_name: "Jaidee", first_name_th: "สมชาย", last_name_th: "ใจดี",
                                admission_year_be: 2536, status: "graduated", program: @cs_old, study_track: "regular")
    @misfiled = Student.create!(student_id: "C518744", first_name: "Boonchai", last_name: "S", first_name_th: "บุญชัย", last_name_th: "โสวรรณ",
                                admission_year_be: 2535, status: "retired", program: @cp_0018)
    @xml = %(<document><page id="page1" width="500" height="700">
      #{line_xml(50, 10, 'รุ่น CE01')}
      #{line_xml(50, 20, 'นางสาว กนกพรรณ กีรติสุนทร')}
      #{line_xml(50, 30, 'รุ่น CS23')}
      #{line_xml(50, 40, 'นาย สมชาย ใจดี')}
      #{line_xml(50, 50, 'นาย มานะ อดทน')}
      #{line_xml(50, 60, 'รุ่น CT04')}
      #{line_xml(50, 70, 'นาง มาลี (แซ่ลี้) รักดี')}
      #{line_xml(50, 80, 'รุ่น CM01')}
      #{line_xml(50, 90, 'ผศ. บุญชัย โสวรรณ')}
    </page></document>)
    @dir = Book30::Directory.new(@xml)
    @out = Dir.mktmpdir
  end

  teardown { FileUtils.remove_entry(@out) }

  def importer(commit:)
    Book30::Importer.new(directory: @dir, commit: commit, out_dir: Pathname(@out), io: StringIO.new)
  end

  test "dry run classifies, writes CSVs, and changes nothing" do
    result = nil
    assert_no_difference [ "Student.count", "Book30Entry.count" ] do
      result = importer(commit: false).run
    end
    assert_equal 5, result[:lines]
    # CE01 is the only cohort with an empty pool (CM01's pool holds the re-filed student);
    # มานะ (CS23) and มาลี (CT04) have DB students in their cohort but no candidate.
    assert_equal({ "create_book_only_cohort" => 1, "linked_exact" => 2, "create_missing" => 2 }, result[:outcomes])
    assert_equal 1, result[:refiled]
    assert_equal @cp_0018, @misfiled.reload.program, "dry run must roll the CM re-file back"
    assert File.exist?(File.join(@out, "decisions.csv"))
    assert File.exist?(File.join(@out, "summary.csv"))
  end

  test "commit re-files CM, links, and creates placeholders with the documented shape" do
    importer(commit: true).run
    assert_equal @cm_first, @misfiled.reload.program
    assert_match(/re-filed from 0018 to 0037/, @misfiled.remark)
    assert_equal 5, Book30Entry.count
    linked = Book30Entry.find_by!(cohort: "CS23", line_no: 1)
    assert_equal "linked_exact", linked.outcome
    assert_equal @existing, linked.student
    assert_equal "สมชาย", @existing.reload.first_name_th, "linked students are never modified"

    cm = Book30Entry.find_by!(cohort: "CM01", line_no: 1)
    assert_equal "linked_exact", cm.outcome
    assert_equal @misfiled, cm.student

    ce = Book30Entry.find_by!(cohort: "CE01", line_no: 1).student
    assert_equal "B30-CE01-001", ce.student_id
    assert_equal [ nil, nil, "กนกพรรณ", "กีรติสุนทร", 2512, "unknown", "book30", "F", nil ],
                 [ ce.first_name, ce.last_name, ce.first_name_th, ce.last_name_th, ce.admission_year_be, ce.status, ce.source, ce.sex, ce.study_track ]
    assert_equal @ce_prog, ce.program

    ct = Book30Entry.find_by!(cohort: "CT04", line_no: 1)
    assert_equal "create_missing", ct.outcome
    assert_equal [ "special", @cs_old, "แซ่ลี้" ], [ ct.student.study_track, ct.student.program, ct.alias_name ]
    assert_match(/30-year book CT04 line 1/, ct.student.remark)

    missing = Book30Entry.find_by!(cohort: "CS23", line_no: 2).student
    assert_equal [ "regular", @cs_old, "B30-CS23-002" ], [ missing.study_track, missing.program, missing.student_id ]
  end

  test "refuses a second commit; rollback removes entries and placeholders only" do
    importer(commit: true).run
    io = StringIO.new
    assert_nil Book30::Importer.new(directory: @dir, commit: true, out_dir: Pathname(@out), io: io).run
    assert_match(/Refusing/, io.string)

    assert_difference("Student.count", -3) do
      assert_difference("Book30Entry.count", -5) { Book30::Rollback.new(commit: true, io: StringIO.new).run }
    end
    assert Student.exists?(@existing.id)
    assert Student.exists?(@misfiled.id)
  end
end
