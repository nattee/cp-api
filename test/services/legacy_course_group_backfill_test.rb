require "test_helper"
require "tmpdir"
require "csv"

class LegacyCourseGroupBackfillTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("legacy-backfill-test")
    @program = programs(:cp_bachelor) # program_code "2101"
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  def run_backfill(commit: true)
    LegacyCourseGroupBackfill.new(run_dir: @dir, commit: commit).call
  end

  test "creates the pairing named by the legacy prefix" do
    course = Course.create!(course_no: "2110997", revision_year_be: 2565, name: "Legacy",
                            course_group: "2101-MS")
    counts = run_backfill
    assert_equal 1, counts[:created]
    assert_equal "2101-MS",
                 ProgramCourse.find_by(program: @program, course: course).course_group_code
  end

  test "fills a blank tag on an existing pairing" do
    pc = program_courses(:gened_cp)
    pc.course.update!(course_group: "2101-GENED")
    counts = run_backfill
    assert_equal 1, counts[:filled]
    assert_equal "2101-GENED", pc.reload.course_group_code
  end

  test "never overwrites an existing differing tag" do
    pc = program_courses(:intro_cp) # tag "2101-C"
    pc.course.update!(course_group: "2101-OTHER")
    counts = run_backfill
    assert_equal 1, counts[:tag_discrepancies]
    assert_equal "2101-C", pc.reload.course_group_code
  end

  test "skips and reports unparseable values and unknown program codes" do
    Course.create!(course_no: "2110996", revision_year_be: 2565, name: "Bad1",
                   course_group: "Project")
    Course.create!(course_no: "2110995", revision_year_be: 2565, name: "Bad2",
                   course_group: "9999-C")
    counts = run_backfill
    # 3, not 2: the senior_project fixture ships legacy course_group "Project",
    # which every run_backfill in this file also processes (unparseable).
    assert_equal 3, counts[:unparseable]
    reasons = CSV.read(File.join(@dir, "skipped_rows.csv"), headers: true).map { |r| r["reason"] }
    assert_includes reasons, "unparseable format"
    assert_includes reasons, "unknown program code"
  end

  test "leaves placeholder-program links alone and reports them" do
    placeholder = Program.placeholder
    course = Course.create!(course_no: "2110994", revision_year_be: 2565, name: "Ph",
                            course_group: "2101-C")
    ProgramCourse.create!(program: placeholder, course: course)
    counts = run_backfill
    assert_equal 1, counts[:placeholder_links]
    assert ProgramCourse.exists?(program: placeholder, course: course), "placeholder link deleted"
    assert ProgramCourse.exists?(program: @program, course: course), "correct pairing not created"
  end

  test "dry-run writes nothing" do
    course = Course.create!(course_no: "2110993", revision_year_be: 2565, name: "Dry",
                            course_group: "2101-C")
    counts = run_backfill(commit: false)
    assert_equal 1, counts[:creatable]
    assert_nil ProgramCourse.find_by(program: @program, course: course)
  end
end
