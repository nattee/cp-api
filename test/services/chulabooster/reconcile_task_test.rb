require "test_helper"
require "tmpdir"

class Chulabooster::ReconcileTaskTest < ActiveSupport::TestCase
  test "load_checkpoint marks entities with a local_only.csv as completed" do
    Dir.mktmpdir("recon-task") do |dir|
      File.write(File.join(dir, "programs_local_only.csv"), "key\n")
      File.write(File.join(dir, "checkpoint.json"),
                 { entity: "courses", next_cursor: "abc", done: false }.to_json)
      cp = Chulabooster.load_checkpoint(dir)
      assert_includes cp[:completed], "programs"
      assert_equal "courses", cp[:in_progress]
      assert_equal "abc", cp[:next_cursor]
    end
  end

  test "mappers registry returns all five in order" do
    assert_equal %w[programs courses students program_courses student_courses],
                 Chulabooster.mappers.map(&:entity)
  end
end
