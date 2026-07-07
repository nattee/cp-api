require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::ProgramCourseSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("pc-sync-test")
    @program = programs(:cp_bachelor)          # program_code "2101"
    @linked_blank = program_courses(:gened_cp) # pairing exists, no tag
    @linked_tagged = program_courses(:intro_cp) # pairing exists, tag "2101-C"
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # CB row builder. course_id = "<CE year><course_no>".
  def cb_row(course, tag, program_code: "2101")
    { "program_id"        => program_code,
      "course_id"         => "#{course.revision_year_be - 543}#{course.course_no}",
      "course_no"         => course.course_no,
      "course_group_code" => tag,
      "course_type"       => 9 }
  end

  def run_sync(rows, commit: false)
    Chulabooster::ProgramCourseSync.new(client: FakeClient.new(rows), run_dir: @dir,
                                        commit: commit).call
  end

  test "creates a missing pairing with the CB tag on commit" do
    course = Course.create!(course_no: "2110999", revision_year_be: 2565, name: "New")
    counts = run_sync([cb_row(course, "2101-C")], commit: true)
    assert_equal 1, counts[:created]
    assert_equal "2101-C", ProgramCourse.find_by(program: @program, course: course).course_group_code
  end

  test "fills a blank tag, mirrors course_type" do
    counts = run_sync([cb_row(@linked_blank.course, "2101-GSP")], commit: true)
    assert_equal 1, counts[:filled]
    @linked_blank.reload
    assert_equal "2101-GSP", @linked_blank.course_group_code
    assert_equal 9, @linked_blank.course_type
  end

  test "never overwrites a differing tag — reports it" do
    counts = run_sync([cb_row(@linked_tagged.course, "2101-DIFFERENT")], commit: true)
    assert_equal 1, counts[:tag_discrepancies]
    assert_equal "2101-C", @linked_tagged.reload.course_group_code
    disc = CSV.read(File.join(@dir, "tag_discrepancies.csv"), headers: true)
    assert_equal "2101-DIFFERENT", disc.first["cb"]
  end

  test "identical tag is a no-op" do
    counts = run_sync([cb_row(@linked_tagged.course, "2101-C")], commit: true)
    assert_equal 1, counts[:identical]
    assert_equal 0, counts[:filled] + counts[:created] + counts[:tag_discrepancies]
  end

  test "unresolvable program or course is skipped and reported" do
    ghost = cb_row(courses(:intro_computing), "9999-C", program_code: "9999")
    counts = run_sync([ghost], commit: true)
    assert_equal 1, counts[:unresolved]
    skipped = CSV.read(File.join(@dir, "skipped_rows.csv"), headers: true)
    assert_equal "program not found", skipped.first["reason"]
  end

  test "dry-run writes nothing" do
    course = Course.create!(course_no: "2110998", revision_year_be: 2565, name: "New2")
    counts = run_sync([cb_row(course, "2101-C"), cb_row(@linked_blank.course, "2101-GSP")])
    assert_equal 1, counts[:creatable]
    assert_equal 1, counts[:fillable]
    assert_nil ProgramCourse.find_by(program: @program, course: course)
    assert_nil @linked_blank.reload.course_group_code
  end
end
