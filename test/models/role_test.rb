require "test_helper"

class RoleTest < ActiveSupport::TestCase
  # --- effective_permission_keys: implications + inheritance ---

  test "a grades.read-only role effectively holds students.read_minimal" do
    role = Role.new(name: "stats_only", permission_keys: ["grades.read"])
    assert_includes role.effective_permission_keys, "students.read_minimal"
  end

  test "a students.read_full-only role effectively holds students.read_minimal" do
    role = Role.new(name: "full_no_min", permission_keys: ["students.read_full"])
    assert_includes role.effective_permission_keys, "students.read_minimal"
  end

  test "a courses.read-only role gains no student access" do
    role = Role.new(name: "courses_only", permission_keys: ["courses.read"])
    assert_not_includes role.effective_permission_keys, "students.read_minimal"
  end

  test "effective keys still include inherited ancestor keys" do
    keys = roles(:staff).effective_permission_keys
    assert_includes keys, "courses.read"          # inherited from public_info
    assert_includes keys, "students.read_minimal" # inherited from minimal
    assert_includes keys, "grades.read"           # own
  end
end
