# Frozen catalog of every permission the app enforces. NOT an ActiveRecord
# model: each key is backed by enforcement code (a before_action, a view
# conditional, a LINE tool gate), so adding a key is inherently a code change.
# Roles (DB rows, admin-editable) bundle these keys — only the bundling is data.
module Permission
  CATALOG = {
    "courses.read"          => "Course offerings, sections, schedules, staff directory, basic course info",
    "students.read_minimal" => "Any student: ID, name, program, admission year (fields are limited, not rows)",
    "students.read_full"    => "Any student: everything incl. status, contact, and course history (not grade values)",
    "grades.read"           => "Grade values, GPA, distributions, and grade-derived reports for any student",
    "advisees.read_full"    => "Own advisees only: everything incl. grades (inert without advisorships)",
    "users.manage"          => "Administration: users, roles, imports, scrapes, and all writes"
  }.freeze

  KEYS = CATALOG.keys.freeze

  # Structural containment: granting the left key is meaningless (or unsafe)
  # without the right keys, so effective permission sets always include them.
  # - grades.read exposes student identity (names + IDs) through grade reports
  #   and the schedule roster, so it cannot be held without the identity key.
  # - students.read_full is a strict superset of the minimal fields, and the
  #   students controller gates every action on students.read_minimal.
  # Expanded once, at the end of Role#effective_permission_keys.
  IMPLICATIONS = {
    "grades.read"        => %w[students.read_minimal],
    "students.read_full" => %w[students.read_minimal]
  }.freeze

  # Given granted keys, return them plus every key they structurally imply.
  # Fixed-point, so a future chained implication still fully resolves.
  def self.expand(keys)
    result = Set.new(keys)
    loop do
      implied = Set.new(result.flat_map { |k| IMPLICATIONS[k] || [] })
      break if implied.subset?(result)
      result |= implied
    end
    result
  end

  def self.valid_key?(key) = CATALOG.key?(key)

  def self.label(key) = CATALOG[key]
end
