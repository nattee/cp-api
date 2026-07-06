require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::GradeSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("grade-sync-test")
    # An in-progress enrollment (nil grade) as this sync itself creates them — the
    # nil->value fill path.
    @in_progress = Grade.create!(student: students(:graduated_student),
                                 course: courses(:senior_project),
                                 year_ce: 2023, semester: 1, grade: nil, source: "imported")
    @identical  = grades(:active_intro_computing)   # A, imported, 2024 s1
    @stale      = grades(:graduated_intro_computing) # A, imported, 2022 s1 -> CB says B
    @manual     = grades(:active_gened)              # B, manual, 2024 s1  -> CB says A
    @to_nil     = grades(:active_senior_project)     # B+, imported, 2024 s2 -> CB blank
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # CB student_courses row. course_id = "<CE revision year><course_no>"; semester_code is
  # "S1"/"s2"-style; credits_grant arrives as a float.
  def cb_row(grade_or_nil = nil, student: nil, course: nil, year: nil, semester: nil,
             cb_grade:, credits_grant: nil, revision_year_be: nil, course_no: nil)
    g = grade_or_nil
    student ||= g.student
    course_no ||= (course || g.course).course_no
    rev_be = revision_year_be || (course || g.course).revision_year_be
    { "course_id"     => "#{rev_be - 543}#{course_no}",
      "student_id"    => student.student_id,
      "academic_year" => year || g&.year_ce,
      "semester_code" => "S#{semester || g&.semester}",
      "grade"         => cb_grade,
      "credits_grant" => credits_grant }
  end

  def cb_rows
    new_enrollment = cb_row(student: students(:active_student), course: courses(:intro_computing),
                            year: 2025, semester: 1, cb_grade: "", credits_grant: 0.0)
    [
      cb_row(@identical, cb_grade: "A"),                                    # identical
      cb_row(@stale, cb_grade: "B", credits_grant: 3.0),                    # value->value correct
      cb_row(@in_progress, cb_grade: "A", credits_grant: 3.0),              # nil->value fill
      cb_row(@manual, cb_grade: "A", credits_grant: 3.0),                   # manual -> report only
      cb_row(@to_nil, cb_grade: ""),                                        # value->nil -> report only
      { "course_id" => "FOR_ETL", "student_id" => students(:active_student).student_id,
        "academic_year" => 2016, "semester_code" => "S2", "grade" => "",
        "credits_grant" => 0.0 },                                           # sentinel
      cb_row(student: students(:active_student), course: courses(:intro_computing),
             year: 2023, semester: 2, cb_grade: "D", credits_grant: 3.0,
             revision_year_be: 2566),                                       # matched IGNORING revision?
      # ^ no: (active_student, 2110101, 2023, 2) has no local grade -> CB-only, but rev 2566
      #   doesn't exist locally -> ladder copies closest revision (2565).
      cb_row(student: students(:graduated_student), year: 2022, semester: 2, cb_grade: "C+",
             credits_grant: 3.0, course_no: "5500111", course: nil,
             revision_year_be: 2566),                                       # CB-only, unknown course -> placeholder
      new_enrollment,                                                       # CB-only, blank grade
      new_enrollment.dup,                                                   # duplicate CB row
      cb_row(student: Student.new(student_id: "1111111111"),
             course: courses(:intro_computing), year: 2024, semester: 1,
             cb_grade: "A", credits_grant: 3.0)                             # unknown student
    ]
  end

  test "dry-run computes everything and writes NOTHING to the database" do
    counts = nil
    assert_no_difference ["Grade.count", "Course.count"] do
      counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir).call
    end

    assert_equal 11, counts[:cb_rows]
    assert_equal 1, counts[:sentinel]
    assert_equal 1, counts[:unknown_student]
    assert_equal 5, counts[:matched]
    assert_equal 1, counts[:identical]
    assert_equal 2, counts[:correctable] # stale value->value + nil->value fill
    assert_equal 0, counts[:corrected]
    assert_equal 1, counts[:manual_diff]
    assert_equal 1, counts[:value_to_nil]
    assert_equal 3, counts[:creatable]   # copied-ladder D, placeholder C+, blank enrollment
    assert_equal 1, counts[:ladder_copied]
    assert_equal 1, counts[:ladder_placeholder]
    assert_equal 1, counts[:duplicate_cb]
    assert_equal 0, counts[:errors]

    assert_equal "A", @stale.reload.grade, "dry-run must not correct"
    assert_nil @in_progress.reload.grade, "dry-run must not fill"

    corrections = CSV.read(File.join(@dir, "grade_corrections.csv"))[1..]
    assert_equal 2, corrections.length
    disc = CSV.read(File.join(@dir, "grade_discrepancies.csv"))[1..]
    assert_equal %w[manual value_to_nil], disc.map(&:last).sort
    skipped = CSV.read(File.join(@dir, "skipped_unknown_students.csv"))[1..]
    assert_equal [["1111111111", "2110101", "2024", "1", "A"]], skipped
    ladder = CSV.read(File.join(@dir, "ladder_courses.csv"))[1..]
    assert_equal [["2110101", "2566", "copied", "2565"], ["5500111", "2566", "placeholder", nil]],
                 ladder
  end

  test "commit corrects stale values, fills nil grades, creates CB-only rows, protects manual" do
    counts = nil
    assert_difference "Grade.count", 3 do
      assert_difference "Course.count", 2 do
        counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir,
                                             commit: true).call
      end
    end
    assert_equal 2, counts[:corrected]
    assert_equal 3, counts[:created]

    @stale.reload
    assert_equal "B", @stale.grade
    assert_equal 3.0, @stale.grade_weight.to_f
    assert_equal 3, @stale.credits_grant
    assert_equal courses(:intro_computing), @stale.course, "never re-linked to another revision"

    @in_progress.reload
    assert_equal "A", @in_progress.grade
    assert_equal 4.0, @in_progress.grade_weight.to_f

    assert_equal "B", @manual.reload.grade, "manual rows are never modified"
    assert_equal "B+", @to_nil.reload.grade, "CB blank never blanks a local value"

    copied = Course.find_by!(course_no: "2110101", revision_year_be: 2566)
    assert_equal "copied", copied.auto_generated
    assert_equal courses(:intro_computing).name, copied.name

    placeholder = Course.find_by!(course_no: "5500111", revision_year_be: 2566)
    assert_equal "placeholder", placeholder.auto_generated
    assert_equal "5500111", placeholder.name
    assert_empty placeholder.programs

    blank = Grade.find_by!(student: students(:active_student),
                           course: courses(:intro_computing), year_ce: 2025, semester: 1)
    assert_nil blank.grade
    assert_nil blank.credits_grant, "CB's 0.0 for in-progress must not become earned-0"
    assert_equal "chulabooster", blank.source
  end

  test "commit run is idempotent — second run corrects and creates nothing" do
    Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    dir2 = Dir.mktmpdir("grade-sync-test-2")
    begin
      counts = nil
      assert_no_difference ["Grade.count", "Course.count"] do
        counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: dir2,
                                             commit: true).call
      end
      assert_equal 0, counts[:corrected]
      assert_equal 0, counts[:created]
      # matched = 11 rows - 1 sentinel - 1 unknown student = 9: the 5 originally-matched keys,
      # the 3 rows created by run 1, and the former duplicate row (now just another matched hit).
      assert_equal 9, counts[:matched]
      # identical = 7: original identical + the 2 corrected-by-run-1 rows + the 3 created rows
      # (the blank enrollment compares nil==nil with forced-nil credits) + the ex-duplicate.
      assert_equal 7, counts[:identical]
      assert_equal 0, counts[:duplicate_cb]
      # manual + value->nil diffs persist as report-only every run:
      assert_equal 1, counts[:manual_diff]
      assert_equal 1, counts[:value_to_nil]
    ensure
      FileUtils.remove_entry(dir2)
    end
  end
end
