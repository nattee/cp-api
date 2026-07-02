require "test_helper"
require "tmpdir"

class Chulabooster::ReconcilerTest < ActiveSupport::TestCase
  # A client stub whose each_page yields canned pages for one entity.
  class FakeClient
    def initialize(pages) = @pages = pages   # [[rows, next_cursor], ...]
    def each_page(_entity, start_cursor: nil)
      @pages.each { |rows, cursor| yield rows, cursor }
    end
  end

  setup do
    @dir = Dir.mktmpdir("recon-test")
    @writer = Chulabooster::ReportWriter.new(@dir)
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  test "buckets identical / changed / cb_only / local_only for programs" do
    p = programs(:cp_bachelor)
    identical = { "program_id" => p.program_code, "program_name" => p.name_en, "program_name_alt" => p.name_th,
                  "revision_year" => p.year_started - 543, "program_code" => p.alternative_program_code }
    changed = { "program_id" => programs(:cp_master).program_code, "program_name" => "X",
                "program_name_alt" => "Y", "revision_year" => 2000, "program_code" => "Z" }
    cb_only = { "program_id" => "999999999999", "program_name" => "Ghost" }
    client = FakeClient.new([[[identical, changed], "c1"], [[cb_only], nil]])

    counts = Chulabooster::Reconciler.new(client: client, writer: @writer, run_dir: @dir)
                                     .reconcile_entity(Chulabooster::Mappers::Programs.new)

    assert_equal Program.count, counts[:local]
    assert_equal 3, counts[:cb]
    assert_equal 1, counts[:identical]
    assert_equal 1, counts[:changed]
    assert_equal 1, counts[:cb_only]
    assert_equal Program.count - 2, counts[:local_only] # all locals except the two matched
    assert_path_exists File.join(@dir, "programs_changed.csv")
    assert_path_exists File.join(@dir, "programs_cb_only.csv")
    assert_path_exists File.join(@dir, "checkpoint.json")
  end

  test "reconcile writes nothing to the database (read-only)" do
    client = FakeClient.new([[[{ "program_id" => "999999999999", "program_name" => "Ghost" }], nil]])
    assert_no_difference ["Program.count", "ProgramCourse.count", "Course.count", "Student.count", "Grade.count"] do
      Chulabooster::Reconciler.new(client: client, writer: @writer, run_dir: @dir)
                              .reconcile_entity(Chulabooster::Mappers::Programs.new)
    end
  end

  test "write_summary produces summary.md and a console table" do
    counts = [{ entity: "programs", local: 46, cb: 260, matched: 44, identical: 40, changed: 4, cb_only: 216, local_only: 2 }]
    table = @writer.write_summary(counts)
    assert_match "programs", table
    assert_path_exists File.join(@dir, "summary.md")
  end
end
