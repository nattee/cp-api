require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::CourseSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("course-sync-test")
    # A local auto-generated shell, as the CSV GradeImporter ladder creates them.
    @shell = Course.create!(course_no: "2110502", revision_year_be: 2557,
                            name: "2110502", auto_generated: "placeholder")
    # A "copied" clone whose guessed name is wrong (the 2110471 course-number-reuse case) —
    # user decision 2026-07-06: clones are backfilled like placeholders.
    @clone = Course.create!(course_no: "2110471", revision_year_be: 2539,
                            name: "COMPUTER NETWORKS I", credits: 3, l_credits: 3,
                            auto_generated: "copied")
    @real = courses(:intro_computing)
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # Builds a CB export row that mirrors a local course exactly (identical under comparison).
  # CB sends CE years and float numerics; names compare case-insensitively via Convert.norm.
  def cb_row_for(course, **overrides)
    { "course_no"        => course.course_no,
      "revision_year"    => course.revision_year_be - 543,
      "course_name"      => course.name.to_s.upcase,
      "course_name_alt"  => course.name_th,
      "course_name_abbr" => course.name_abbr,
      "credits"          => course.credits&.to_f,
      "l_credits"        => course.l_credits&.to_f,
      "l_hours"          => course.l_hours&.to_f,
      "nl_hours"         => course.nl_hours&.to_f,
      "s_hours"          => course.s_hours&.to_f,
      "is_thesis"        => course.is_thesis ? 1.0 : 0.0,
      "gened"            => course.is_gened ? 1 : nil }.merge(overrides)
  end

  def cb_rows
    [
      cb_row_for(@real),                                       # matched real, identical
      cb_row_for(@real, "credits" => 4.0),                     # 2nd row for same course: real diff
      cb_row_for(@shell, "course_name" => "FORMAL VERIFICATION",
                 "course_name_alt" => "การทวนสอบเชิงรูปนัย",
                 "course_name_abbr" => "FORMAL VER",
                 "credits" => 3.0, "l_credits" => 3.0, "l_hours" => 3.0,
                 "nl_hours" => 0.0, "s_hours" => 0.0),          # shell -> backfill
      cb_row_for(@clone, "course_name" => "COMPUTER ARCHITECTURE",
                 "course_name_alt" => "สถาปัตยกรรมคอมพิวเตอร์"), # divergent clone -> backfill fixes name
      { "course_no" => "2110999", "revision_year" => 2023,
        "course_name" => "NEW COURSE", "course_name_alt" => "วิชาใหม่",
        "course_name_abbr" => "NEW C", "credits" => 3.0, "l_credits" => 3.0,
        "l_hours" => 3.0, "nl_hours" => 0.0, "s_hours" => 0.0,
        "is_thesis" => 0.0, "gened" => nil }                    # CB-only -> create
    ]
  end

  test "dry-run computes everything and writes NOTHING to the database" do
    counts = nil
    assert_no_difference "Course.count" do
      counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir).call
    end

    assert_equal 5, counts[:cb_rows]
    assert_equal 2, counts[:matched_real] # identical row + the credits-diff row
    assert_equal 1, counts[:creatable]
    assert_equal 0, counts[:created]
    assert_equal 2, counts[:backfillable] # shell + divergent clone
    assert_equal 1, counts[:discrepancies]
    assert_equal 0, counts[:errors]

    @shell.reload
    assert_equal "2110502", @shell.name, "dry-run must not backfill"
    assert_equal "placeholder", @shell.auto_generated
    @clone.reload
    assert_equal "COMPUTER NETWORKS I", @clone.name, "dry-run must not backfill clones"
    assert_equal "copied", @clone.auto_generated
    assert_equal 3, @real.reload.credits, "real rows are never written"

    disc = CSV.read(File.join(@dir, "course_discrepancies.csv"))[1..]
    assert_equal [["2110101", "2565", "credits", "3", "4"]], disc
  end

  test "commit creates CB-only courses and backfills shells, promoting them to none" do
    counts = nil
    assert_difference "Course.count", 1 do
      counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir,
                                            commit: true).call
    end
    assert_equal 1, counts[:created]
    assert_equal 2, counts[:backfilled]

    created = Course.find_by!(course_no: "2110999", revision_year_be: 2566) # 2023 CE -> BE
    assert_equal "NEW COURSE", created.name
    assert_equal "วิชาใหม่", created.name_th
    assert_equal 3, created.credits            # float coerced to int
    assert_equal "none", created.auto_generated
    assert_not created.is_thesis
    assert_empty created.programs

    @shell.reload
    assert_equal "FORMAL VERIFICATION", @shell.name
    assert_equal "การทวนสอบเชิงรูปนัย", @shell.name_th
    assert_equal 3, @shell.credits
    assert_equal "none", @shell.auto_generated, "backfilled shell is promoted"

    @clone.reload
    assert_equal "COMPUTER ARCHITECTURE", @clone.name, "registrar data replaces the clone guess"
    assert_equal "none", @clone.auto_generated, "backfilled clone is promoted"

    assert_equal 3, @real.reload.credits, "real-row diff is report-only even in commit"
  end

  test "commit run is idempotent — second run creates and backfills nothing" do
    Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    dir2 = Dir.mktmpdir("course-sync-test-2")
    begin
      counts = nil
      assert_no_difference "Course.count" do
        counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: dir2,
                                              commit: true).call
      end
      assert_equal 0, counts[:created]
      assert_equal 0, counts[:backfilled], "backfilled rows are now real rows"
      assert_equal 5, counts[:matched_real] # identical + diff-row + ex-shell + ex-clone + created
    ensure
      FileUtils.remove_entry(dir2)
    end
  end
end
