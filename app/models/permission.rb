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

  def self.valid_key?(key) = CATALOG.key?(key)

  def self.label(key) = CATALOG[key]
end
