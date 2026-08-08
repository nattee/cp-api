require "test_helper"

class PermissionTest < ActiveSupport::TestCase
  # --- Structural implications (Permission.expand) ---
  # These guard the security invariant that grade/full-student access can never
  # be granted without the identity key the reports and LINE tools assume.

  test "grades.read implies students.read_minimal" do
    assert_includes Permission.expand(["grades.read"]), "students.read_minimal"
  end

  test "students.read_full implies students.read_minimal" do
    assert_includes Permission.expand(["students.read_full"]), "students.read_minimal"
  end

  test "expand preserves the granted keys" do
    assert_includes Permission.expand(["grades.read"]), "grades.read"
  end

  test "courses.read implies nothing extra" do
    assert_equal Set.new(["courses.read"]), Permission.expand(["courses.read"])
  end

  test "expand of no keys is empty" do
    assert_empty Permission.expand([])
  end

  test "expand is idempotent" do
    once = Permission.expand(["grades.read"])
    assert_equal once, Permission.expand(once)
  end
end
