require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::StudentSyncTest < ActiveSupport::TestCase
  # Client stub: StudentSync only uses each_row("students").
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("sync-test")
    cs = ProgramGroup.create!(code: "CS", name_en: "Computer Science", degree_level: "master",
                              degree_name: "Test Degree", field_of_study: "Computer Engineering")
    @cs_prog = Program.create!(program_group: cs, program_code: "9102",
                               year_started_be: 2561, short_name: "T")
    @matched = students(:active_student) # student_id 6732100021, CP, status active
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # One row per interesting path. CB pads names with trailing spaces — kept here on purpose.
  def cb_rows
    [
      # new, clean CS resolution, graduated
      { "student_id" => "6570000121", "start_academic_year" => 2022, "major_code" => "21101",
        "firstname" => "Somchai   ", "lastname" => "Jaidee  ", "firstname_alt" => "สมชาย ",
        "lastname_alt" => "ใจดี ", "gender" => "M", "student_status" => "13" },
      # new, 21100 + segment 70 -> CM heuristic -> remark flag
      { "student_id" => "6070200021", "start_academic_year" => 2017, "major_code" => "21100",
        "firstname" => "Malee", "lastname" => "Rakdee", "firstname_alt" => "มาลี",
        "lastname_alt" => "รักดี", "gender" => "F", "student_status" => "00" },
      # new, unknown status code -> status "unknown" + report
      { "student_id" => "6570000221", "start_academic_year" => 2022, "major_code" => "21101",
        "firstname" => "Wichai", "lastname" => "Meedee", "firstname_alt" => "วิชัย",
        "lastname_alt" => "มีดี", "gender" => "M", "student_status" => "77" },
      # new but unresolvable (unmapped major code)
      { "student_id" => "4931802021", "start_academic_year" => 2006, "major_code" => "99999",
        "firstname" => "Lost", "lastname" => "Track", "firstname_alt" => "ล",
        "lastname_alt" => "ท", "gender" => "M", "student_status" => "13" },
      # new but invalid (blank lastname) -> row error
      { "student_id" => "6570000321", "start_academic_year" => 2022, "major_code" => "21101",
        "firstname" => "NoLast", "lastname" => "", "firstname_alt" => "น",
        "lastname_alt" => "ล", "gender" => "M", "student_status" => "13" },
      # matched (fixture): CB says graduated ("13") but local is active -> stale-active report;
      # major 21100 + segment "32" -> CP == local CP -> NO program discrepancy
      { "student_id" => @matched.student_id, "start_academic_year" => 2024, "major_code" => "21100",
        "firstname" => "Thanawat", "lastname" => "Sricharoen", "firstname_alt" => "ธนวัฒน์",
        "lastname_alt" => "ศรีเจริญ", "gender" => "M", "student_status" => "13" }
    ]
  end

  test "dry-run computes everything and writes NOTHING to the database" do
    counts = nil
    assert_no_difference ["Student.count", "Program.count", "Grade.count"] do
      counts = Chulabooster::StudentSync.new(client: FakeClient.new(cb_rows), run_dir: @dir).call
    end

    assert_equal 1, counts[:matched]
    assert_equal 5, counts[:cb_only]
    assert_equal 3, counts[:creatable]
    assert_equal 0, counts[:created]
    assert_equal 1, counts[:unresolved]
    assert_equal 1, counts[:errors]
    assert_equal 1, counts[:unknown_status]
    assert_equal 1, counts[:heuristic_flagged]
    assert_equal 0, counts[:program_discrepancies]
    assert_equal 1, counts[:status_discrepancies]
    assert_equal 1, counts[:stale_active]

    assert_nil @matched.reload.cb_status_code, "dry-run must not mirror cb_status_code"

    %w[created_students unresolved_students row_errors students_program_discrepancies
       students_status_discrepancies unknown_status_codes].each do |f|
      assert_path_exists File.join(@dir, "#{f}.csv")
    end
    assert_equal 0, csv_rows("students_program_discrepancies").length, "no program discrepancy expected"
    assert_equal [["6570000321", "Last name can't be blank"]], csv_rows("row_errors")
    assert_equal [[@matched.student_id, "active", "13", "graduated"]], csv_rows("students_status_discrepancies")
    assert_equal [["6570000221", "77"]], csv_rows("unknown_status_codes")
  end

  test "commit creates the resolvable students with stripped names, derived status, and remark flags" do
    counts = nil
    assert_difference "Student.count", 3 do
      counts = Chulabooster::StudentSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    end
    assert_equal 3, counts[:created]

    clean = Student.find_by!(student_id: "6570000121")
    assert_equal "Somchai", clean.first_name          # trailing CB padding stripped
    assert_equal "ใจดี", clean.last_name_th
    assert_equal 2565, clean.admission_year_be        # 2022 CE -> BE
    assert_equal @cs_prog, clean.program
    assert_equal "graduated", clean.status
    assert_equal "13", clean.cb_status_code
    assert_nil clean.remark, "clean direct resolution needs no assumption flag"

    flagged = Student.find_by!(student_id: "6070200021")
    assert_equal "CM", flagged.program.program_group.code
    assert_match(/inferred from student_id pattern/, flagged.remark)

    unknown = Student.find_by!(student_id: "6570000221")
    assert_equal "unknown", unknown.status
    assert_equal "77", unknown.cb_status_code

    # matched student: cb_status_code mirrored, but status NEVER auto-corrected
    assert_equal "13", @matched.reload.cb_status_code
    assert_equal "active", @matched.status
  end

  test "commit run is idempotent — a second run creates nothing and reports the students as matched" do
    Chulabooster::StudentSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    dir2 = Dir.mktmpdir("sync-test-2")
    begin
      counts = nil
      assert_no_difference "Student.count" do
        counts = Chulabooster::StudentSync.new(client: FakeClient.new(cb_rows), run_dir: dir2, commit: true).call
      end
      assert_equal 4, counts[:matched] # original fixture match + the 3 created
      assert_equal 0, counts[:created]
    ensure
      FileUtils.remove_entry(dir2)
    end
  end

  private

  def csv_rows(name)
    CSV.read(File.join(@dir, "#{name}.csv"))[1..] || []
  end
end
