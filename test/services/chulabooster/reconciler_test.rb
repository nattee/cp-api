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
                  "revision_year" => p.year_started_be - 543, "program_code" => p.alternative_program_code }
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

  test "resume seeds counts from a prior checkpoint instead of restarting at zero (resume-summary bug regression)" do
    p1 = programs(:cp_bachelor)
    p2 = programs(:cp_master)

    # Simulate that a prior (crashed) run already processed one row and left a checkpoint behind.
    partial_counts = { entity: "programs", local: Program.count, cb: 1, matched: 1, identical: 1,
                        changed: 0, cb_only: 0, local_only: 0 }
    File.write(File.join(@dir, "checkpoint.json"),
               JSON.generate(entity: "programs", next_cursor: "resume-here", counts: partial_counts, done: false))

    # The "resumed" run only sees a second page (as if the real client resumed from the saved cursor).
    row2 = { "program_id" => p2.program_code, "program_name" => "Changed", "program_name_alt" => p2.name_th,
             "revision_year" => p2.year_started_be - 543, "program_code" => p2.alternative_program_code }
    client = FakeClient.new([[[row2], nil]])

    counts = Chulabooster::Reconciler.new(client: client, writer: @writer, run_dir: @dir)
                                     .reconcile_entity(Chulabooster::Mappers::Programs.new, start_cursor: "resume-here")

    # The pre-crash page's counts must still be reflected, not lost.
    assert_equal 2, counts[:cb]          # 1 from before the crash + 1 from this resumed page
    assert_equal 1, counts[:identical]   # carried over from before the crash
    assert_equal 1, counts[:changed]     # from this resumed page (program_name mismatch)
  end

  test "ReportWriter persists and reloads per-entity counts (used by the rake task to preserve the summary across resume)" do
    counts = { entity: "programs", local: 46, cb: 260, matched: 44, identical: 40, changed: 4, cb_only: 216, local_only: 2 }
    @writer.write_counts("programs", counts)
    reloaded = @writer.read_counts("programs")
    assert_equal counts, reloaded
    assert_nil @writer.read_counts("courses") # nothing written yet for this entity
  end
end
