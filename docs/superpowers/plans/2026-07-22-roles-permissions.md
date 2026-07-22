# Roles & Permissions System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unused admin/editor/viewer string roles with a permission system: a frozen permission catalog in code, admin-editable Role records with DAG inheritance, an advisorships table for scoped advisee access, and enforcement in both the web UI and the LINE tool pipeline.

**Architecture:** Permissions are a frozen constant (`Permission::CATALOG`) because every key is backed by enforcement code. Roles are DB rows bundling keys, connected by `role_inheritances` edges (a DAG); a role's effective permissions are its own ∪ ancestors'. "Advisor" is not a role: `advisees.read_full` is a scoped permission that only activates for users whose linked Staff has current `advisorships` rows. Web enforcement via `require_permission` before_actions and tiered views; LINE enforcement via role-filtered tool definitions, an executor re-check, and in-tool per-student checks.

**Tech Stack:** Rails 8.1, MySQL 8, HAML, Minitest fixtures. Spec: `docs/superpowers/specs/2026-07-22-roles-permissions-design.md`.

## Global Constraints

- **Version control is Mercurial (hg), not git.** No `.git` exists. Never run git commands.
- **ANOTHER CLAUDE SESSION IS ACTIVELY WORKING IN THIS REPO.** Every commit MUST name its files explicitly: `hg add <new files>` then `hg commit <file1> <file2> ... -m "..."`. NEVER `hg commit` bare, NEVER `hg addremove`. Before each commit run `hg status` and touch only your own files. Commit at the end of every task, immediately.
- **Commit messages lead with WHY** (first paragraph = problem/motivation), then what changed. End with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **No TDD.** Project convention: new tests are written after the feature, in a separate discussion. But the EXISTING suite must stay green — tasks include targeted `bin/rails test <file>` runs and fixture/test maintenance where our changes break current tests. Do not write brand-new test files.
- **Run tests with `bin/rails test <path>`** (never `bin/rails test:system <path>` — the file arg is ignored there and all 101 system tests run).
- **Role names are underscore slugs**: `admin`, `staff`, `minimal`, `public_info`. Badges derive `badge-#{name.dasherize}`.
- **Permission keys** (exact strings, used everywhere): `courses.read`, `students.read_minimal`, `students.read_full`, `grades.read`, `advisees.read_full`, `users.manage`.
- Dev DB runs on **port 3308** (WSL mirrored networking); `bin/rails` handles this via database.yml — no manual mysql flags needed.
- HAML is indentation-sensitive: when a step says "replace the file/block", replace exactly as shown; do not re-indent surrounding code.

---

### Task 1: Permission catalog, Role + RoleInheritance models, roles migration, fixtures

**Files:**
- Create: `app/models/permission.rb`
- Create: `app/models/role.rb`
- Create: `app/models/role_inheritance.rb`
- Create: `db/migrate/*_create_roles_and_role_inheritances.rb` (via generator)
- Create: `test/fixtures/roles.yml`
- Create: `test/fixtures/role_inheritances.yml`

**Interfaces:**
- Produces: `Permission::CATALOG` (Hash key→label), `Permission::KEYS`, `Permission.valid_key?(key)`, `Permission.label(key)`
- Produces: `Role#effective_permission_keys` → `Set[String]`, `Role#ancestor_role_ids` → `Array[Integer]`, `Role#display_name` → String, `Role#parent_role_ids=` (via has_many :parent_roles), `Role#users`, `Role#child_roles`, boolean `locked`
- Produces: fixture labels `roles(:admin)`, `roles(:staff)`, `roles(:minimal)`, `roles(:public_info)`

- [ ] **Step 1: Create the permission catalog**

`app/models/permission.rb`:

```ruby
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
```

- [ ] **Step 2: Generate the migration**

Run: `bin/rails generate migration CreateRolesAndRoleInheritances`

Replace the generated file's content with:

```ruby
class CreateRolesAndRoleInheritances < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :description
      # MySQL json columns cannot have defaults; the model normalizes nil → [].
      t.json :permission_keys
      t.boolean :locked, null: false, default: false
      t.timestamps
    end

    create_table :role_inheritances do |t|
      t.references :role, null: false, foreign_key: true
      t.references :parent_role, null: false, foreign_key: { to_table: :roles }
      t.timestamps
    end
    add_index :role_inheritances, [:role_id, :parent_role_id], unique: true
  end
end
```

- [ ] **Step 3: Create the Role model**

`app/models/role.rb`:

```ruby
# A named bundle of permissions, editable by admins at /roles. Roles form a
# DAG via role_inheritances: effective permissions are the role's own
# permission_keys plus everything from its ancestors. Keys must come from
# Permission::CATALOG — the catalog is code, the bundling is data.
class Role < ApplicationRecord
  has_many :users, dependent: :restrict_with_error

  has_many :role_inheritances, dependent: :destroy, inverse_of: :role
  has_many :parent_roles, through: :role_inheritances
  has_many :child_inheritances, class_name: "RoleInheritance",
           foreign_key: :parent_role_id, dependent: :restrict_with_error,
           inverse_of: :parent_role
  has_many :child_roles, through: :child_inheritances, source: :role

  validates :name, presence: true, uniqueness: true
  validate :permission_keys_in_catalog
  validate :locked_role_immutable, on: :update

  before_destroy :prevent_locked_destroy

  def permission_keys
    super || []
  end

  def display_name
    name.titleize
  end

  # Own keys ∪ all ancestors' keys. BFS with a visited set: edges are
  # cycle-validated on write, but a stale cycle must never hang a request.
  def effective_permission_keys
    keys = Set.new
    visited = Set.new
    queue = [self]
    while (role = queue.shift)
      next if role.id && visited.include?(role.id)
      visited << role.id if role.id
      keys.merge(role.permission_keys)
      queue.concat(role.parent_roles.to_a)
    end
    keys
  end

  def ancestor_role_ids
    ids = []
    visited = Set.new
    queue = parent_roles.to_a
    while (role = queue.shift)
      next if visited.include?(role.id)
      visited << role.id
      ids << role.id
      queue.concat(role.parent_roles.to_a)
    end
    ids
  end

  private

  def permission_keys_in_catalog
    invalid = permission_keys.reject { |k| Permission.valid_key?(k) }
    errors.add(:permission_keys, "contains unknown keys: #{invalid.join(', ')}") if invalid.any?
  end

  # The seeded admin role is locked so an admin cannot lock themselves out by
  # unchecking users.manage on their own role.
  def locked_role_immutable
    errors.add(:base, "This role is locked and cannot be modified.") if locked? && changed?
  end

  def prevent_locked_destroy
    if locked?
      errors.add(:base, "This role is locked and cannot be deleted.")
      throw :abort
    end
  end
end
```

- [ ] **Step 4: Create the RoleInheritance model**

`app/models/role_inheritance.rb`:

```ruby
# One DAG edge: `role` inherits everything `parent_role` grants. Cycles are
# rejected here (an edge role→parent is a cycle iff role is already an
# ancestor of parent).
class RoleInheritance < ApplicationRecord
  belongs_to :role, inverse_of: :role_inheritances
  belongs_to :parent_role, class_name: "Role", inverse_of: :child_inheritances

  validates :parent_role_id, uniqueness: { scope: :role_id }
  validate :not_self
  validate :no_cycle
  validate :child_not_locked

  private

  def not_self
    errors.add(:parent_role, "cannot be the role itself") if role_id.present? && role_id == parent_role_id
  end

  def no_cycle
    return if role.nil? || parent_role.nil? || role_id == parent_role_id
    if parent_role.id == role.id || parent_role.ancestor_role_ids.include?(role.id)
      errors.add(:parent_role, "would create an inheritance cycle")
    end
  end

  def child_not_locked
    errors.add(:base, "Locked roles cannot change inheritance.") if role&.locked?
  end
end
```

- [ ] **Step 5: Create fixtures**

`test/fixtures/roles.yml`:

```yaml
admin:
  name: admin
  description: Administrator - everything
  permission_keys: ["courses.read", "students.read_minimal", "students.read_full", "grades.read", "advisees.read_full", "users.manage"]
  locked: true

staff:
  name: staff
  description: Department staff - full read access, advisee access via advisorships
  permission_keys: ["students.read_full", "grades.read", "advisees.read_full"]

minimal:
  name: minimal
  description: Minimal student access - identity, program, admission year
  permission_keys: ["students.read_minimal"]

public_info:
  name: public_info
  description: Public-by-nature data - course offerings and basic course info
  permission_keys: ["courses.read"]
```

`test/fixtures/role_inheritances.yml`:

```yaml
minimal_from_public:
  role: minimal
  parent_role: public_info

staff_from_minimal:
  role: staff
  parent_role: minimal
```

- [ ] **Step 6: Migrate and verify the DAG logic**

Run: `bin/rails db:migrate`
Expected: migration applies cleanly; `db/schema.rb` gains both tables.

Run:

```bash
bin/rails runner '
ActiveRecord::Base.transaction do
  a = Role.create!(name: "t_base",  permission_keys: ["courses.read"])
  b = Role.create!(name: "t_mid",   permission_keys: ["students.read_minimal"])
  c = Role.create!(name: "t_top",   permission_keys: ["grades.read"])
  RoleInheritance.create!(role: b, parent_role: a)
  RoleInheritance.create!(role: c, parent_role: b)
  raise "expand failed" unless c.effective_permission_keys == Set.new(["grades.read", "students.read_minimal", "courses.read"])
  cyc = RoleInheritance.new(role: a, parent_role: c)
  raise "cycle accepted!" if cyc.valid?
  bad = Role.new(name: "t_bad", permission_keys: ["nope.read"])
  raise "bad key accepted!" if bad.valid?
  puts "DAG expansion, cycle rejection, catalog validation: OK"
  raise ActiveRecord::Rollback
end'
```

Expected output: `DAG expansion, cycle rejection, catalog validation: OK`

- [ ] **Step 7: Commit**

```bash
hg add app/models/permission.rb app/models/role.rb app/models/role_inheritance.rb db/migrate/*_create_roles_and_role_inheritances.rb test/fixtures/roles.yml test/fixtures/role_inheritances.yml
hg commit app/models/permission.rb app/models/role.rb app/models/role_inheritance.rb db/migrate/*_create_roles_and_role_inheritances.rb test/fixtures/roles.yml test/fixtures/role_inheritances.yml db/schema.rb -m "Add permission catalog and Role model with DAG inheritance

Every logged-in user can read everything today; upcoming user populations
(LINE-linked students, minimal-access staff, advisors) need scoped access,
and role bundles must be editable without a deploy. Permissions stay a
frozen code catalog (each key is backed by enforcement code); roles become
DB rows bundling keys, joined by cycle-validated inheritance edges.

- Permission module: 6-key frozen catalog
- Role: permission_keys json, effective_permission_keys BFS, locked flag
- RoleInheritance: DAG edges, cycle/self/duplicate validation
- roles + role_inheritances fixtures (admin/staff/minimal/public_info)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: users.role_id — migrate off the role string, rewrite User, update every call site

**Files:**
- Create: `db/migrate/*_move_users_to_role_records.rb` (via generator)
- Modify: `app/models/user.rb` (full replacement below)
- Modify: `db/seeds.rb`
- Modify: `app/views/users/_form.html.haml:58-62`
- Modify: `app/views/users/index.html.haml` (badge line 28, `@users` eager load via controller)
- Modify: `app/views/users/show.html.haml:22`
- Modify: `app/controllers/users_controller.rb` (`user_params`, index eager load)
- Modify: `app/controllers/line_contacts_controller.rb` (`new_user`, `user_params`)
- Modify: `app/views/line_contacts/new_user.html.haml` (role select)
- Modify: `test/fixtures/users.yml`
- Modify: `test/models/user_test.rb` and any test referencing role strings

**Interfaces:**
- Consumes: `Role`, `Permission` from Task 1.
- Produces: `User#role` (belongs_to Role, null: false), `User#can?(key)` → bool, `User#admin?` (= `can?("users.manage")`), new-user default role `public_info`. `User::ROLES`, `User::ROLE_ICONS`, `#editor?`, `#viewer?` are GONE — nothing may reference them after this task.

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration MoveUsersToRoleRecords`

Replace content with:

```ruby
class MoveUsersToRoleRecords < ActiveRecord::Migration[8.1]
  # Table-only stand-ins: migrations must not depend on app models.
  class MigRole < ActiveRecord::Base
    self.table_name = "roles"
  end

  # The four seed roles are created HERE (not only in db/seeds.rb) because the
  # role_id backfill needs them, and existing DBs migrate rather than reseed.
  # db/seeds.rb repeats them idempotently for fresh schema-loaded installs.
  ROLE_ROWS = {
    "public_info" => { description: "Public-by-nature data - course offerings and basic course info",
                       permission_keys: ["courses.read"], locked: false },
    "minimal"     => { description: "Minimal student access - identity, program, admission year",
                       permission_keys: ["students.read_minimal"], locked: false },
    "staff"       => { description: "Department staff - full read access, advisee access via advisorships",
                       permission_keys: ["students.read_full", "grades.read", "advisees.read_full"], locked: false },
    "admin"       => { description: "Administrator - everything",
                       permission_keys: ["courses.read", "students.read_minimal", "students.read_full",
                                         "grades.read", "advisees.read_full", "users.manage"], locked: true }
  }.freeze

  def up
    add_reference :users, :role, foreign_key: true

    ids = {}
    ROLE_ROWS.each do |name, attrs|
      row = MigRole.find_or_create_by!(name: name) { |r| r.assign_attributes(attrs) }
      ids[name] = row.id
    end
    [%w[minimal public_info], %w[staff minimal]].each do |child, parent|
      execute <<~SQL.squish
        INSERT INTO role_inheritances (role_id, parent_role_id, created_at, updated_at)
        SELECT #{ids[child]}, #{ids[parent]}, NOW(), NOW()
        WHERE NOT EXISTS (SELECT 1 FROM role_inheritances
                          WHERE role_id = #{ids[child]} AND parent_role_id = #{ids[parent]})
      SQL
    end

    execute "UPDATE users SET role_id = #{ids['admin']} WHERE role = 'admin'"
    # editor was never actually checked anywhere; both tiers are department
    # insiders and keep their current read-everything access as staff.
    execute "UPDATE users SET role_id = #{ids['staff']} WHERE role IN ('editor', 'viewer')"

    change_column_null :users, :role_id, false
    remove_column :users, :role
  end

  def down
    add_column :users, :role, :string, null: false, default: "viewer"
    execute <<~SQL.squish
      UPDATE users u JOIN roles r ON r.id = u.role_id
      SET u.role = CASE r.name WHEN 'admin' THEN 'admin' ELSE 'viewer' END
    SQL
    remove_reference :users, :role
  end
end
```

Run: `bin/rails db:migrate`
Expected: applies cleanly; verify with `bin/rails runner 'puts User.group("roles.name").joins(:role).count rescue puts User.first.attributes["role_id"]'` — hold off until Step 2 rewrites the model; instead verify raw: `bin/rails runner 'puts ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM users WHERE role_id IS NULL")'` → `0`.

- [ ] **Step 2: Rewrite the User model**

Replace `app/models/user.rb` entirely with:

```ruby
class User < ApplicationRecord
  has_secure_password

  belongs_to :role

  # Least-privilege default: new accounts (manual creation and the LINE
  # quick-link flow alike) start as public_info until an admin raises them.
  before_validation on: :create do
    self.role ||= Role.find_by(name: "public_info")
  end

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :uid, uniqueness: { scope: :provider }, allow_nil: true
  # The form's "Default" option submits "" — normalize to nil so the
  # allow_nil inclusion below treats "no preference" consistently.
  normalizes :llm_model, with: ->(model) { model.presence }
  validates :llm_model, inclusion: { in: LLM_CONFIG[:models].keys.map(&:to_s) }, allow_nil: true

  scope :active, -> { where(active: true) }

  # Effective permission check — the single entry point for authorization.
  # Memoized per instance; role edits take effect on the next request.
  def can?(key)
    permission_set.include?(key)
  end

  def admin?
    can?("users.manage")
  end

  private

  def permission_set
    @permission_set ||= role&.effective_permission_keys || Set.new
  end
end
```

- [ ] **Step 3: Update seeds**

In `db/seeds.rb`, replace the super-admin block at the top with:

```ruby
# Roles must exist before any user row — users.role_id is NOT NULL. The same
# four roles are created by the MoveUsersToRoleRecords migration on migrated
# DBs; a fresh install loads schema.rb (no migration data), so seeds repeat
# them idempotently here.
{
  "public_info" => { description: "Public-by-nature data - course offerings and basic course info",
                     permission_keys: ["courses.read"], locked: false, parents: [] },
  "minimal"     => { description: "Minimal student access - identity, program, admission year",
                     permission_keys: ["students.read_minimal"], locked: false, parents: ["public_info"] },
  "staff"       => { description: "Department staff - full read access, advisee access via advisorships",
                     permission_keys: ["students.read_full", "grades.read", "advisees.read_full"],
                     locked: false, parents: ["minimal"] },
  "admin"       => { description: "Administrator - everything",
                     permission_keys: Permission::KEYS.dup, locked: true, parents: [] }
}.each do |name, attrs|
  role = Role.find_or_create_by!(name: name) do |r|
    r.description = attrs[:description]
    r.permission_keys = attrs[:permission_keys]
    r.locked = attrs[:locked]
  end
  attrs[:parents].each do |parent_name|
    parent = Role.find_by!(name: parent_name)
    RoleInheritance.find_or_create_by!(role: role, parent_role: parent)
  end
end

# Super admin user (ID 1)
User.find_or_create_by!(id: 1) do |u|
  u.username = "root"
  u.email = "nattee@cp.eng.chula.ac.th"
  u.name = "dae (superadmin)"
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = Role.find_by!(name: "admin")
end
```

(Keep the rest of seeds.rb — the `Dir[...seeds/*.rb]` loop, `Program.placeholder`, the final `puts` — unchanged.)

- [ ] **Step 4: Update the users form**

In `app/views/users/_form.html.haml`, replace the role block (currently lines 58–62, the `f.label :role` + `f.select :role` + error lines) with:

```haml
  .mb-3
    = f.label :role_id, "Role", class: "form-label"
    = f.select :role_id, options_for_select(Role.order(:name).map { |r| [r.display_name, r.id] }, user.role_id), {}, class: "form-select #{'is-invalid' if user.errors[:role].any?}", data: { controller: "select2" }
    - if user.errors[:role].any?
      .invalid-feedback= user.errors[:role].first
```

- [ ] **Step 5: Update users index + show views and controller**

`app/views/users/index.html.haml` line 28 — replace:

```haml
                %span.badge{class: "badge-#{user.role}"}= user.role.titleize
```

with:

```haml
                %span.badge{class: "badge-role badge-#{user.role.name.dasherize}"}= user.role.display_name
```

`app/views/users/show.html.haml` line 22 — same replacement pattern with `@user`:

```haml
        %span.badge{class: "badge-role badge-#{@user.role.name.dasherize}"}= @user.role.display_name
```

`app/controllers/users_controller.rb`:
- `def index` body → `@users = User.includes(:role).all`
- In `user_params`, replace `:role` with `:role_id` in the permit list.

- [ ] **Step 6: Update the LINE quick-link flow**

`app/controllers/line_contacts_controller.rb`:
- In `new_user`, replace `role: "viewer"` with `role: Role.find_by(name: "public_info")`.
- In `user_params`, replace `:role` with `:role_id`.

`app/views/line_contacts/new_user.html.haml`: find the role select (`grep -n ":role" app/views/line_contacts/new_user.html.haml`). Replace the `f.select :role ... User::ROLES ...` line with:

```haml
            = f.select :role_id, options_for_select(Role.order(:name).map { |r| [r.display_name, r.id] }, @user.role_id), {}, class: "form-select", data: { controller: "select2" }
```

(keep the surrounding label/wrapper lines; only the select changes). If the view hardcodes role text elsewhere, adjust the copy to say the default is Public Info.

- [ ] **Step 7: Update fixtures and hunt down stale references**

`test/fixtures/users.yml` — the `role:` values now resolve as **associations to roles.yml labels**. Set: `admin:` user → `role: admin`; `editor:`, `viewer:`, `inactive:` users → `role: staff` (they are department insiders; existing tests assume they can read but not administrate). Append two new fixtures for later tiers:

```yaml
minimal:
  username: minimal_user
  email: minimal@example.com
  name: Minimal User
  password_digest: "<%= password_digest %>"
  role: minimal
  active: true

public_info:
  username: public_user
  email: public@example.com
  name: Public Info User
  password_digest: "<%= password_digest %>"
  role: public_info
  active: true
```

Then hunt down every remaining reference to the old API:

Run: `grep -rn "User::ROLES\|ROLE_ICONS\|\.editor?\|\.viewer?\|role: \"viewer\"\|role: \"editor\"\|role: \"admin\"\|role == " app/ test/ db/ lib/ --include="*.rb" --include="*.haml" --include="*.yml"`

Fix each hit using this mapping: string `"admin"` → `roles(:admin)` / `Role.find_by(name: "admin")`; `"editor"`/`"viewer"` → `roles(:staff)` (tests) — in `test/models/user_test.rb` delete tests of `editor?`/`viewer?`/ROLES inclusion and re-point `admin?` tests at fixtures (`users(:admin).admin?` still true, `users(:viewer).admin?` still false). Test files constructing `User.new(... role: "viewer" ...)` become `role: roles(:staff)`.

- [ ] **Step 8: Run affected tests**

Run: `bin/rails test test/models/user_test.rb test/controllers/users_controller_test.rb test/controllers/line_contacts_controller_test.rb`
Expected: PASS (fix any straggler with the Step 7 mapping).

Run: `bin/rails test` (full unit/controller suite — system tests excluded by default)
Expected: PASS. Failures here are stale role-string references; fix with the same mapping.

- [ ] **Step 9: Commit**

```bash
hg commit db/migrate/*_move_users_to_role_records.rb db/schema.rb app/models/user.rb db/seeds.rb app/views/users/_form.html.haml app/views/users/index.html.haml app/views/users/show.html.haml app/controllers/users_controller.rb app/controllers/line_contacts_controller.rb app/views/line_contacts/new_user.html.haml test/fixtures/users.yml test/models/user_test.rb -m "Move users from role strings to Role records

The admin/editor/viewer strings gated nothing but writes (editor was never
checked at all), and role bundles could only change via deploy. Users now
reference Role rows: the migration seeds the four roles, maps admin→admin
and editor/viewer→staff (both tiers are trusted insiders today), and drops
the string column. New accounts default to public_info — least privilege —
which also covers the LINE quick-link flow.

- User#can?(key) via role's effective (DAG-expanded) permission set
- admin? = can?(\"users.manage\"); editor?/viewer?/ROLES removed
- forms select role_id from the DB; fixtures point at roles.yml

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Include any additional test files you had to fix in the commit file list.)

---

### Task 3: users.staff_id, advisorships table, scoped-access helpers

**Files:**
- Create: `db/migrate/*_add_staff_link_and_advisorships.rb` (via generator)
- Create: `app/models/advisorship.rb`
- Modify: `app/models/user.rb`, `app/models/student.rb`, `app/models/staff.rb`
- Modify: `app/views/users/_form.html.haml` (staff select), `app/views/users/show.html.haml` (staff row)
- Modify: `app/controllers/users_controller.rb` (`user_params`)
- Create: `test/fixtures/advisorships.yml`

**Interfaces:**
- Consumes: `User#can?` from Task 2.
- Produces: `Advisorship` (belongs_to :student, :staff; scope `.current`; `#current?`), `Student#advisors` / `Student#current_advisorships` / `Student#advisorships`, `Staff#current_advisees` / `Staff#current_advisorships` / `Staff#advisorships`, `User#staff` (optional), `User#advisee_ids` → Array[Integer], `User#advisee?(student)`, `User#can_view_student_fully?(student)`, `User#can_view_grades?(student)`.

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration AddStaffLinkAndAdvisorships`

```ruby
class AddStaffLinkAndAdvisorships < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :staff, foreign_key: true

    create_table :advisorships do |t|
      t.references :student, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :started_on, null: false
      t.date :ended_on
      t.string :note
      t.timestamps
    end
    add_index :advisorships, [:student_id, :staff_id, :ended_on]
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Create the Advisorship model**

`app/models/advisorship.rb`:

```ruby
# One advisor↔advisee assignment. History-preserving: reassignment sets
# ended_on and adds a new row; ended rows grant no access. Overlapping
# active rows are legal (grad co-advisors), but the same (student, staff)
# pair may be active only once.
class Advisorship < ApplicationRecord
  belongs_to :student
  belongs_to :staff

  validates :started_on, presence: true
  validates :student_id, uniqueness: { scope: :staff_id,
                                       conditions: -> { where(ended_on: nil) },
                                       message: "already has this staff member as a current advisor" }
  validate :ended_after_started

  scope :current, -> { where(ended_on: nil) }

  def current? = ended_on.nil?

  private

  def ended_after_started
    return if ended_on.blank? || started_on.blank?
    errors.add(:ended_on, "must be on or after the start date") if ended_on < started_on
  end
end
```

- [ ] **Step 3: Wire associations and helpers**

`app/models/student.rb` — after `has_many :grades, dependent: :destroy` add:

```ruby
  has_many :advisorships, dependent: :destroy
  has_many :current_advisorships, -> { current }, class_name: "Advisorship", inverse_of: :student
  has_many :advisors, through: :current_advisorships, source: :staff
```

`app/models/staff.rb` — after `has_many :sections, through: :teachings` add:

```ruby
  has_many :advisorships, dependent: :destroy
  has_many :current_advisorships, -> { current }, class_name: "Advisorship", inverse_of: :staff
  has_many :current_advisees, through: :current_advisorships, source: :student
```

`app/models/user.rb` — under `belongs_to :role` add `belongs_to :staff, optional: true`, and add these public methods after `admin?`:

```ruby
  # Current advisee student IDs via the linked Staff record; empty when the
  # account has no staff link. Memoized per request.
  def advisee_ids
    @advisee_ids ||= staff ? staff.current_advisorships.pluck(:student_id) : []
  end

  def advisee?(student)
    advisee_ids.include?(student.id)
  end

  # Composite scoped checks — single source of truth; views and LINE tools
  # must use these, never re-derive the advisee logic.
  def can_view_student_fully?(student)
    can?("students.read_full") || (can?("advisees.read_full") && advisee?(student))
  end

  def can_view_grades?(student)
    can?("grades.read") || (can?("advisees.read_full") && advisee?(student))
  end
```

- [ ] **Step 4: User form + show + params**

`app/views/users/_form.html.haml` — insert directly after the role block from Task 2:

```haml
  .mb-3
    = f.label :staff_id, "Staff record", class: "form-label"
    = f.select :staff_id, options_for_select([["— none —", ""]] + Staff.order(:first_name).map { |s| [s.display_name_th, s.id] }, user.staff_id), {}, class: "form-select", data: { controller: "select2" }
    .form-text Links this account to a Staff record — determines whose advisees they can fully access.
```

`app/views/users/show.html.haml` — directly after the role `%dd` row add:

```haml
        %dt.col-sm-3 Staff record
        %dd.col-sm-9
          - if @user.staff
            = link_to @user.staff.display_name_th, @user.staff
          - else
            %span.text-muted — none —
```

(Match the surrounding `%dt`/`%dd` indentation exactly — check the file first.)

`app/controllers/users_controller.rb` `user_params`: add `:staff_id` to the permit list.

- [ ] **Step 5: Fixtures**

Fixture labels confirmed to exist: `lecturer_smith` in staffs.yml, `active_student` in students.yml.

`test/fixtures/advisorships.yml` (labels verified against existing fixtures):

```yaml
one_current:
  student: active_student
  staff: lecturer_smith
  started_on: 2025-08-01
```

- [ ] **Step 6: Verify**

```bash
bin/rails runner '
ActiveRecord::Base.transaction do
  staff = Staff.first or raise "need staff seed"
  student = Student.first or raise "need student seed"
  u = User.first
  u.update!(staff: staff)
  Advisorship.create!(student: student, staff: staff, started_on: Date.current)
  raise "advisee_ids failed" unless User.find(u.id).advisee_ids.include?(student.id)
  dup = Advisorship.new(student: student, staff: staff, started_on: Date.current)
  raise "dup active pair accepted!" if dup.valid?
  puts "advisorships OK"
  raise ActiveRecord::Rollback
end'
```

Expected: `advisorships OK`. Then `bin/rails test test/models` → PASS.

- [ ] **Step 7: Commit**

```bash
hg add app/models/advisorship.rb db/migrate/*_add_staff_link_and_advisorships.rb test/fixtures/advisorships.yml
hg commit app/models/advisorship.rb db/migrate/*_add_staff_link_and_advisorships.rb db/schema.rb app/models/user.rb app/models/student.rb app/models/staff.rb app/views/users/_form.html.haml app/views/users/show.html.haml app/controllers/users_controller.rb test/fixtures/advisorships.yml -m "Add advisorships and link user accounts to staff records

Advisor access is data, not a role: advisees.read_full sits in the staff
bundle and activates only for users whose linked Staff has current
advisorship rows — becoming an advisor means recording the advisorship,
with no role flip to remember. The join table keeps history (ended_on)
and allows co-advisors while blocking duplicate active pairs.

- users.staff_id connects a login to its Staff record
- User#advisee_ids / #can_view_student_fully? / #can_view_grades? are the
  single source of truth for scoped checks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: require_permission + controller read gates + per-report access

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify (add gate, delete local `require_admin` def): `students_controller.rb`, `grades_controller.rb`, `courses_controller.rb`, `staffs_controller.rb`, `semesters_controller.rb`, `rooms_controller.rb`, `course_offerings_controller.rb`, `programs_controller.rb`
- Modify (add gate only): `program_groups_controller.rb`, `schedules_controller.rb`
- Modify (delete local `require_admin` def only): `users_controller.rb`, `chats_controller.rb`, `chat_messages_controller.rb`, `api_events_controller.rb`, `data_imports_controller.rb`, `data_sources_controller.rb`, `line_contacts_controller.rb`, `program_courses_controller.rb`
- Modify (widen to full admin gate): `scrapes_controller.rb`
- Modify: `app/services/reports/catalog.rb`, `app/services/reports/catalog_entry.rb`, `app/controllers/reports_controller.rb`, `app/controllers/home_controller.rb`
- Modify: affected controller tests (assert-message/redirect fixes only)

**Interfaces:**
- Consumes: `User#can?` (Task 2).
- Produces: `ApplicationController#require_permission(key)` (private, redirects to root with alert "You are not authorized to view that page.") and centralized `#require_admin` (alert "Only admins can perform this action."). `Reports::Catalog.hub_entries(user:)`; `CatalogEntry#access` is now a permission-key String.

- [ ] **Step 1: Central helpers**

In `app/controllers/application_controller.rb`, add to the `private` section after `require_login`:

```ruby
  # Generalized read gate. Writes stay behind require_admin. nil-safe: an
  # expired session hits require_login first, but belt-and-braces here.
  def require_permission(key)
    unless current_user&.can?(key)
      redirect_to root_path, alert: "You are not authorized to view that page."
    end
  end

  # Kept as a named alias (not inlined at call sites) so the existing
  # `before_action :require_admin` lines across controllers keep working.
  def require_admin
    unless current_user&.can?("users.manage")
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
```

- [ ] **Step 2: Gate + dedupe each controller**

For **each** of `courses`, `staffs`, `semesters`, `rooms`, `course_offerings`, `programs`: add below the existing `before_action :require_admin, only: ...` line:

```ruby
  before_action -> { require_permission("courses.read") }
```

and **delete the entire private `def require_admin ... end` block** at the bottom of the file (the central one now applies).

`app/controllers/students_controller.rb`: add `before_action -> { require_permission("students.read_minimal") }` below the require_admin line; delete its local `require_admin` def (lines 159–163). Note: its redirect target changes from `students_path` to `root_path`.

`app/controllers/grades_controller.rb`: add `before_action -> { require_permission("grades.read") }`; delete local `require_admin` def (keep `require_manual_source`).

`app/controllers/program_groups_controller.rb` (currently no before_actions): add at the top of the class:

```ruby
  before_action -> { require_permission("courses.read") }
```

`app/controllers/schedules_controller.rb`: add at the top of the class:

```ruby
  # All schedule reports are courses.read; the student timetable also shows
  # grade values, so it needs grades.read on top.
  before_action -> { require_permission("courses.read") }
  before_action -> { require_permission("grades.read") }, only: :student
```

`app/controllers/scrapes_controller.rb`: replace `before_action :require_admin, only: %i[create]` with `before_action :require_admin` (scrape history is an ops page — index/show were reachable by every logged-in user) and delete the local `require_admin` def.

For `users` (keep `require_admin_or_self` untouched), `chats`, `chat_messages`, `api_events`, `data_imports`, `data_sources`, `line_contacts`, `program_courses`: delete the local private `def require_admin ... end` block only. The `before_action :require_admin` lines stay and now hit the central helper. (Custom alert texts like "Only admins can access LINE contacts." are replaced by the central message — Step 4 fixes the test assertions.)

- [ ] **Step 3: Per-report access keys**

`app/services/reports/catalog_entry.rb` — update the `access` doc comment on the Struct (no structural change): access is now a permission-key String consumed by `Catalog.hub_entries(user:)` and `ReportsController#show`.

`app/services/reports/catalog.rb` — replace the `entries` list and builders so every entry carries an explicit permission key:

```ruby
    def entries
      [
        # --- Schedules (timetables + the "is my timetable broken?" check) ---
        external("schedules_room",            "Room Schedule",        "Room usage across the week for a semester",        :schedules, :schedules_room_path,       access: "courses.read"),
        external("schedules_staff",           "Staff Schedule",       "A lecturer's weekly timetable and load",           :schedules, :schedules_staff_path,      access: "courses.read"),
        external("schedules_student",         "Student Timetable",    "A student's weekly schedule with grades",          :schedules, :schedules_student_path,    access: "grades.read"),
        external("schedules_curriculum",      "Curriculum Calendar",  "Combined weekly calendar for a set of courses",    :schedules, :schedules_curriculum_path, access: "courses.read"),
        external("schedules_conflicts",       "Conflict Detection",   "Room and staff double-bookings for a semester",    :schedules, :schedules_conflicts_path,  access: "courses.read"),
        # --- Teaching (teaching analytics: matrices + per-lecturer year) ---
        external("schedules_workload",        "Staff Workload",       "Teaching load per lecturer across semesters",      :teaching, :schedules_workload_path,        access: "courses.read"),
        external("schedules_teaching_matrix", "Teaching Matrix",      "Sections taught per lecturer per course",          :teaching, :schedules_teaching_matrix_path, access: "courses.read"),
        registry(Reports::StaffCoursesByYear, "Courses and co-lecturers a lecturer taught in a year, with seats", :teaching, access: "courses.read"),
        # --- Grades & Courses ---
        registry(Reports::SemesterGradeDistribution, "Per-course grade counts and GPA for a program and term", :grades, access: "grades.read"),
        external("grades_distribution",       "Class Grade Distribution", "Grade spread and pass rate per subject across terms", :grades, :distribution_grades_path, access: "grades.read"),
        registry(Reports::FailingStudents,    "Students who received F in a course and term", :grades, access: "grades.read"),
        # --- Students & Cohorts ---
        registry(Reports::CohortGpa,          "Per-term GPA and GPAX for one admission cohort", :students, access: "grades.read"),
        registry(Reports::GroupCreditShortfall, "Students below a credit threshold in a course group", :students, access: "grades.read"),
        registry(Reports::ThesisCredits,      "Enrolled thesis credits per student (master programs)", :students, access: "grades.read"),
        # --- System (admin operational check; not shown in the hub) ---
        registry(Reports::DataCoverage,       "Per-term data-coverage matrix with gaps flagged", :system, access: "users.manage")
      ]
    end

    # Hub list, filtered to what this user may open.
    def hub_entries(user:)
      entries.select { |e| e.hub? && user.can?(e.access) }
    end
```

`grouped` loses its default argument (its old default called the now-user-required `hub_entries`):

```ruby
    # Groups by section in SECTIONS order; only sections present appear.
    def grouped(list)
      list.group_by(&:section)
          .sort_by { |section, _| SECTIONS.keys.index(section) || Float::INFINITY }
          .to_h
    end
```

`app/controllers/home_controller.rb` — the launchpad also lists reports; replace the `index` body:

```ruby
  def index
    @report_sections = Reports::Catalog.grouped(Reports::Catalog.hub_entries(user: current_user))
  end
```

and update the two builders (both now take explicit `access:`):

```ruby
    def external(key, title, description, section, path_helper, access:)
      CatalogEntry.new(key: key, title: title, description: description,
                       section: section, access: access, path_helper: path_helper,
                       report_class: nil)
    end

    def registry(klass, description, section, access:)
      CatalogEntry.new(key: klass.key, title: klass.title, description: description,
                       section: section, access: access, path_helper: nil,
                       report_class: klass)
    end
```

`app/controllers/reports_controller.rb`:
- `index`: `entries = Reports::Catalog.hub_entries(user: current_user)`
- `show`: replace the `if entry.access == :admin && !current_user.admin?` block with:

```ruby
    unless current_user.can?(entry.access)
      return redirect_to(root_path, alert: "You are not authorized to view that report.")
    end
```

Also update the stale comment at the top of the controller (access is now per-report permission keys, not :all/:admin).

- [ ] **Step 4: Repair test expectations, run suite**

Run: `grep -rn "Only admins can access\|assert_redirected_to students_path\|hub_entries" test/ app/ --include="*.rb" | grep -v node_modules`

- `test/controllers/line_contacts_controller_test.rb`: change asserted alert text to "Only admins can perform this action."
- Any students-controller test asserting `assert_redirected_to students_path` after a denied admin action → `root_path`.
- Any other `hub_entries` caller (grep shows them) → pass `user:`.

Run: `bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg commit app/controllers/application_controller.rb app/controllers/students_controller.rb app/controllers/grades_controller.rb app/controllers/courses_controller.rb app/controllers/staffs_controller.rb app/controllers/semesters_controller.rb app/controllers/rooms_controller.rb app/controllers/course_offerings_controller.rb app/controllers/programs_controller.rb app/controllers/program_groups_controller.rb app/controllers/schedules_controller.rb app/controllers/scrapes_controller.rb app/controllers/users_controller.rb app/controllers/chats_controller.rb app/controllers/chat_messages_controller.rb app/controllers/api_events_controller.rb app/controllers/data_imports_controller.rb app/controllers/data_sources_controller.rb app/controllers/line_contacts_controller.rb app/controllers/program_courses_controller.rb app/services/reports/catalog.rb app/services/reports/catalog_entry.rb app/controllers/reports_controller.rb app/controllers/home_controller.rb test/controllers/line_contacts_controller_test.rb -m "Enforce read permissions in controllers and per-report access

Until now every logged-in user could read everything; only writes were
admin-gated. With public_info/minimal accounts arriving via LINE
quick-link, reads need gates too: courses.read for academic-structure
pages, students.read_minimal for the roster, grades.read for grade data.
Reports carry their own key (schedule reports are courses.read; the
student timetable shows grades, so grades.read) and the hub lists only
what the viewer may open. Scrape history joins the ops pages behind
users.manage.

- require_permission/require_admin centralized in ApplicationController;
  12 duplicated private require_admin defs deleted

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Add any other test files you fixed to the file list.)

---

### Task 5: Sidebar + home gating, students index/show tiering

**Files:**
- Modify: `app/views/layouts/application.html.haml:38-124`
- Modify: `app/services/navigation.rb`, `app/views/home/_area_band.html.haml`, `app/views/home/index.html.haml` (launchpad gating)
- Modify: `app/controllers/students_controller.rb` (`datatable`, `set_student`, `order_clause`)
- Modify: `app/views/students/show.html.haml` (full replacement)
- Modify: `test/integration/navigation_parity_test.rb` (if it references the old `access` values)

**Interfaces:**
- Consumes: `User#can?`, `#can_view_student_fully?`, `#can_view_grades?`, `#advisee_ids` (Tasks 2–3).
- Produces: `students#show` assigns `@full_access`, `@grades_visible` (booleans) consumed by the view.

- [ ] **Step 1: Gate the sidebar**

In `app/views/layouts/application.html.haml`, wrap each nav entry per this mapping (indent the existing `%li` blocks one level under the new `- if` lines; the LINE Account entry and the user dropdown stay unconditional):

| Entry | Condition |
|---|---|
| Programs, Courses, Staff | `- if current_user.can?("courses.read")` |
| Students | `- if current_user.can?("students.read_minimal")` |
| Grades | `- if current_user.can?("grades.read")` |
| Reports | `- if current_user.can?("courses.read")` |
| "Teaching" label + Semesters + Rooms | `- if current_user.can?("courses.read")` (one wrapper around all three `%li`) |
| Scraper | `- if current_user.admin?` (ops page, now admin-gated in Task 4) |
| Admin section | already `- if current_user.admin?` — unchanged |

Example for the first group (Programs shown; Courses/Staff follow the same shape inside the same `- if` when contiguous — Programs/Courses/Staff are contiguous, so use ONE wrapper):

```haml
          - if current_user.can?("courses.read")
            %li.nav-item
              = link_to program_groups_path, class: "nav-link d-flex align-items-center #{'active' if controller_name.in?(%w[program_groups programs])}" do
                = resource_icon("program_groups")
                Programs
            %li.nav-item
              = link_to courses_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'courses'}" do
                = resource_icon("courses")
                Courses
            %li.nav-item
              = link_to staffs_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'staffs'}" do
                = resource_icon("staffs")
                Staff
```

- [ ] **Step 2: Gate the home launchpad (Navigation::AREAS)**

The launchpad is data-driven from `app/services/navigation.rb` — do NOT touch the view's structure; retarget the `access` field instead.

In `app/services/navigation.rb`:
- Update the header comment: `:access` is now a `Permission::CATALOG` key, or `nil` for everyone.
- Change each area's `access:` value: `program_groups`, `courses`, `staffs` → `"courses.read"`; `students` → `"students.read_minimal"`; `grades` → `"grades.read"`; `semesters`, `rooms` → `"courses.read"`; `scrapes` → `"users.manage"` (ops page, admin-gated in Task 4); all eight `group: :admin` entries → `"users.manage"`; `line_accounts` → `nil`.
- Replace `visible_to`:

```ruby
  def visible_to(areas, user:)
    areas.select { |a| a[:access].nil? || user.can?(a[:access]) }
  end
```

Both call sites change from `admin: current_user.admin?` to `user: current_user`:
- `app/views/home/_area_band.html.haml`: `- areas = Navigation.visible_to(Navigation.for_group(group), user: current_user)`
- `app/views/home/index.html.haml` ("Your account" band): `Navigation.visible_to(Navigation.for_group(:account), user: current_user)`

The Reports band on home is already user-filtered via the Task 4 `home_controller` change. Keep the Profile card unconditional (it isn't in AREAS).

Run: `bin/rails test test/integration/navigation_parity_test.rb`
Expected: PASS — if it references `access: :admin` or `visible_to(..., admin:)`, update it to the new signature with `users(:admin)` / permission keys.

- [ ] **Step 3: Tier the students controller**

`app/controllers/students_controller.rb`:

In `datatable`, replace the `is_admin = current_user.admin?` line and the `data = students.map` block with:

```ruby
    is_admin = current_user.admin?
    full_access = current_user.can?("students.read_full")
    advisee_ids = current_user.advisee_ids

    data = students.map do |student|
      status_cell =
        if full_access || advisee_ids.include?(student.id)
          render_to_string(partial: "students/status_badge", locals: { student: student }, layout: false)
        else
          "—"
        end
      [
        student.student_id,
        student.display_name,
        student.program&.name_en.to_s,
        ("<span class=\"badge badge-#{student.program&.degree_level}\">#{student.program&.degree_level&.titleize}</span>" if student.program).to_s,
        student.admission_year_be,
        status_cell,
        render_to_string(partial: "students/actions", locals: { student: student, is_admin: is_admin }, layout: false)
      ]
    end
```

In `order_clause`, guard status ordering (sorting the roster by a hidden column would leak status grouping to minimal users) — replace the `column = ...` line with:

```ruby
    column = COLUMNS_MAP[order_col] || "students.student_id"
    column = "students.student_id" if column == "students.status" && !current_user.can?("students.read_full")
```

In `set_student`, replace the body with:

```ruby
    @student = Student.find(params[:id])
    if action_name == "show"
      @full_access = current_user.can_view_student_fully?(@student)
      @grades_visible = current_user.can_view_grades?(@student)
      if @full_access
        @grades = @student.grades.includes(course: { programs: :program_group })
        load_schedule_data
      end
    end
```

- [ ] **Step 4: Tier the student show page**

Replace `app/views/students/show.html.haml` **entirely** with the version below. Changes vs. current: status/graduation/old-program rows, Contact/Guardian/Background/timestamp sections, the Schedule card, and the Course History card render only with `@full_access`; grade values (Grade/Weight columns, GPA lines) additionally require `@grades_visible` (column counts shrink accordingly).

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1= @student.display_name
  .d-flex.gap-2
    - if current_user.admin?
      = link_to "Edit", edit_student_path(@student), class: "btn btn-outline-secondary"
    = link_to "Back", students_path, class: "btn btn-outline-primary"

.card
  .card-body
    .detail-section
      %dl.dl-fields.row.mb-0
        %dt.col-sm-3 Student ID
        %dd.col-sm-9= @student.student_id

        %dt.col-sm-3 Name (EN)
        %dd.col-sm-9= @student.full_name

        - if @student.full_name_th.present?
          %dt.col-sm-3 Name (TH)
          %dd.col-sm-9= @student.full_name_th

    .detail-section
      %h6.section-title Academic
      %dl.dl-fields.row.mb-0
        %dt.col-sm-3 Program
        %dd.col-sm-9
          - if @student.program
            = link_to @student.program.name_en, @student.program
          - else
            .text-muted Not assigned

        - if @full_access && @student.old_program.present?
          %dt.col-sm-3 Old Program
          %dd.col-sm-9= @student.old_program

        %dt.col-sm-3
          Admission Year (B.E.)
          %button.help-popover-trigger{type: "button", tabindex: "0"}
            %span.material-symbols{style: "font-size: 16px"} help
            %span.help-popover-content Buddhist Era year (B.E.). To convert to CE, subtract 543.
        %dd.col-sm-9= @student.admission_year_be

        - if @full_access
          %dt.col-sm-3 Status
          %dd.col-sm-9
            %span.badge{class: "badge-#{@student.status.dasherize}"}= @student.status.titleize

          - if @student.graduation_year_be.present?
            %dt.col-sm-3 Graduation Year (B.E.)
            %dd.col-sm-9= @student.graduation_year_be

    - if @full_access
      - if [@student.email, @student.phone, @student.discord, @student.line_id, @student.address].any?(&:present?)
        .detail-section
          %h6.section-title Contact
          %dl.dl-fields.row.mb-0
            - if @student.email.present?
              %dt.col-sm-3 Email
              %dd.col-sm-9= @student.email

            - if @student.phone.present?
              %dt.col-sm-3 Phone
              %dd.col-sm-9= @student.phone

            - if @student.discord.present?
              %dt.col-sm-3 Discord
              %dd.col-sm-9= @student.discord

            - if @student.line_id.present?
              %dt.col-sm-3 LINE ID
              %dd.col-sm-9= @student.line_id

            - if @student.address.present?
              %dt.col-sm-3 Address
              %dd.col-sm-9= @student.address

      - if [@student.guardian_name, @student.guardian_phone].any?(&:present?)
        .detail-section
          %h6.section-title Guardian
          %dl.dl-fields.row.mb-0
            - if @student.guardian_name.present?
              %dt.col-sm-3 Guardian Name
              %dd.col-sm-9= @student.guardian_name

            - if @student.guardian_phone.present?
              %dt.col-sm-3 Guardian Phone
              %dd.col-sm-9= @student.guardian_phone

      - if [@student.previous_school, @student.enrollment_method, @student.tcas, @student.status_note, @student.remark].any?(&:present?)
        .detail-section
          %h6.section-title Background
          %dl.dl-fields.row.mb-0
            - if @student.previous_school.present?
              %dt.col-sm-3 Previous School
              %dd.col-sm-9= @student.previous_school

            - if @student.enrollment_method.present?
              %dt.col-sm-3 Enrollment Method
              %dd.col-sm-9= @student.enrollment_method

            - if @student.tcas.present?
              %dt.col-sm-3 TCAS Round
              %dd.col-sm-9= @student.tcas

            - if @student.status_note.present?
              %dt.col-sm-3 Status Note
              %dd.col-sm-9= @student.status_note

            - if @student.remark.present?
              %dt.col-sm-3 Remark
              %dd.col-sm-9= @student.remark

      .detail-section
        %dl.dl-fields.row.mb-0
          %dt.col-sm-3 Created at
          %dd.col-sm-9= @student.created_at.strftime("%B %d, %Y %H:%M")

          %dt.col-sm-3 Updated at
          %dd.col-sm-9= @student.updated_at.strftime("%B %d, %Y %H:%M")

- if @full_access && @schedule_semesters&.any?
  .card.mt-3
    .card-body.p-3
      .d-flex.justify-content-between.align-items-center.mb-3
        %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
          %span.material-symbols.resource-icon.me-2 calendar_month
          Schedule
        = form_with(url: student_path(@student), method: :get, class: "d-flex align-items-center gap-2") do |f|
          %label.form-label.mb-0.small.text-muted Semester
          = select_tag :semester_id, options_for_select(@schedule_semesters.map { |s| ["#{s.display_name} — #{Semester::SEMESTER_LABELS[s.semester_number]}", s.id] }, @schedule_semester&.id), class: "form-select form-select-sm", style: "width: auto", data: { controller: "select2" }, onchange: "this.form.requestSubmit()"

      - if @schedule_entries&.any?
        .table-responsive
          %table.table.table-hover.mb-0
            %thead
              %tr
                %th Course No
                %th Course Name
                %th Section
                - if @grades_visible
                  %th.text-center Grade
            %tbody
              - @schedule_entries.each do |entry|
                %tr
                  %td= link_to entry[:grade].course.course_no, entry[:grade].course
                  %td= entry[:grade].course.name
                  %td
                    - if entry[:section]
                      = entry[:section].section_number
                    - else
                      %span.text-muted —
                  - if @grades_visible
                    %td.text-center
                      - if entry[:grade].grade.present?
                        %span.badge{class: entry[:grade].grade_badge_class}= entry[:grade].grade
      - else
        %p.text-muted.mb-0 No schedule data for this semester.

- if @full_access
  .card.mt-3{"data-controller" => "tabs course-filter", "data-course-filter-mode-value" => "rows"}
    .card-body.p-3
      - history_cols = @grades_visible ? 6 : 4
      .d-flex.align-items-center.mb-3.gap-3.flex-wrap
        %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
          %span.material-symbols.resource-icon.me-2 grading
          Course History
        - if @grades.any?
          -# Default to All: a transcript legitimately spans gen-ed/math/language.
          = render "shared/course_filters", scope_default: ""
          .btn-group.btn-group-sm.ms-auto
            %button.btn.btn-outline-secondary.active{"data-tabs-target" => "tab", "data-action" => "click->tabs#switch", "data-index" => "0"}
              By Course Group
            %button.btn.btn-outline-secondary{"data-tabs-target" => "tab", "data-action" => "click->tabs#switch", "data-index" => "1"}
              By Semester

      - if @grades.empty?
        %p.text-muted.mb-0 No grade information available.
      - else
        - if @grades_visible
          - gpa = @student.gpa
          - total_cr = @student.total_credits
          - if gpa
            .mb-3.text-muted
              Cumulative GPA:
              %strong= gpa
              &bull;
              = total_cr
              credits

        -# Tab 1: By Course Group
        .tab-panel{"data-tabs-target" => "panel"}
          - grouped = @grades.sort_by { |g| [g.course.course_group.to_s, g.year_ce, g.semester] }.group_by { |g| g.course.course_group.presence || "Uncategorized" }
          .table-responsive
            %table.table.table-hover.mb-0
              %thead
                %tr
                  %th Course No
                  %th Course Name
                  %th Year/Sem
                  %th.text-center Credits
                  - if @grades_visible
                    %th.text-center Grade
                    %th.text-center Weight
              %tbody
                - grouped.each_with_index do |(group_name, group_grades), group_idx|
                  - group_credits = group_grades.select { |g| g.grade_weight }.sum { |g| g.course.credits.to_i }
                  - group_key = "cg-#{group_name}"
                  - if group_idx.positive?
                    %tr.table-group-spacer{"aria-hidden" => "true", "data-course-filter-target" => "groupRow", "data-course-group" => group_key}
                      %td{colspan: history_cols}
                  %tr.table-group-header{"data-course-filter-target" => "groupRow", "data-course-group" => group_key}
                    %td{colspan: history_cols}
                      %strong= group_name
                      %span.text-muted.ms-2.fw-normal
                        (#{group_credits} credits)
                  - group_grades.each do |g|
                    %tr{"data-course-filter-target" => "row", "data-course-no" => g.course.course_no, "data-course-group" => group_key}
                      %td= link_to g.course.course_no, g.course
                      %td= g.course.name
                      %td= "#{g.year_ce}/#{g.semester}"
                      %td.text-center= g.course.credits
                      - if @grades_visible
                        %td.text-center
                          - if g.grade.present?
                            %span.badge{class: g.grade_badge_class}= g.grade
                        %td.text-center= g.grade_weight

        -# Tab 2: By Semester
        .tab-panel.d-none{"data-tabs-target" => "panel"}
          - by_term = @grades.sort_by { |g| [-g.year_ce, -g.semester] }.group_by { |g| "#{g.year_ce}/#{g.semester}" }
          .table-responsive
            %table.table.table-hover.mb-0
              %thead
                %tr
                  %th Course No
                  %th Course Name
                  %th Course Group
                  %th.text-center Credits
                  - if @grades_visible
                    %th.text-center Grade
                    %th.text-center Weight
              %tbody
                - by_term.each_with_index do |(term_label, term_grades), term_idx|
                  - term_key = "term-#{term_label}"
                  - if term_idx.positive?
                    %tr.table-group-spacer{"aria-hidden" => "true", "data-course-filter-target" => "groupRow", "data-course-group" => term_key}
                      %td{colspan: history_cols}
                  - term_graded = term_grades.select { |g| g.grade_weight }
                  - term_weighted = term_graded.sum { |g| g.grade_weight.to_f * g.course.credits.to_i }
                  - term_credits = term_graded.sum { |g| g.course.credits.to_i }
                  - term_gpa = term_credits.zero? ? nil : (term_weighted / term_credits).round(2)
                  %tr.table-group-header{"data-course-filter-target" => "groupRow", "data-course-group" => term_key}
                    %td{colspan: history_cols}
                      %strong= term_label
                      - if @grades_visible && term_gpa
                        %span.text-muted.ms-2.fw-normal
                          GPA: #{term_gpa}
                          &bull;
                          #{term_credits} credits
                  - term_grades.each do |g|
                    %tr{"data-course-filter-target" => "row", "data-course-no" => g.course.course_no, "data-course-group" => term_key}
                      %td= link_to g.course.course_no, g.course
                      %td= g.course.name
                      %td= g.course.course_group
                      %td.text-center= g.course.credits
                      - if @grades_visible
                        %td.text-center
                          - if g.grade.present?
                            %span.badge{class: g.grade_badge_class}= g.grade
                        %td.text-center= g.grade_weight
```

- [ ] **Step 5: Verify by role**

```bash
bin/rails runner 'u = User.find_or_create_by!(username: "smoke_minimal") { |x| x.email = "smoke_minimal@example.com"; x.name = "Smoke Minimal"; x.password = "password123"; x.role = Role.find_by!(name: "minimal") }; puts u.id'
```

Start the server (`bin/rails server`) and with `AUTO_LOGIN=<that id>` check: sidebar shows Programs/Courses/Staff/Students/Reports but NOT Grades/Scraper/Admin; `/students/<id of any student>` shows only ID/name/program/year (no status, contact, course history); `/grades` redirects with the auth alert. Then re-check as user 1 (admin) that everything still renders. Delete the smoke user after:
`bin/rails runner 'User.find_by(username: "smoke_minimal")&.destroy'`

Run: `bin/rails test test/controllers`
Expected: PASS (system tests run in Task 10).

- [ ] **Step 6: Commit**

```bash
hg commit app/views/layouts/application.html.haml app/services/navigation.rb app/views/home/_area_band.html.haml app/views/home/index.html.haml app/controllers/students_controller.rb app/views/students/show.html.haml test/integration/navigation_parity_test.rb -m "Tier student pages and navigation by permission

Minimal-access users may browse the full roster but see only identity,
program, and admission year — the permission limits fields, not rows. The
student page now renders in tiers: status/contact/history need
students.read_full (or advisee scope), grade values additionally need
grades.read, matching the spec rule that read_full says nothing about
grades. Sidebar and launchpad hide what the viewer cannot open.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Roles admin CRUD UI

**Files:**
- Create: `app/controllers/roles_controller.rb`
- Create: `app/views/roles/index.html.haml`, `show.html.haml`, `new.html.haml`, `edit.html.haml`, `_form.html.haml`
- Modify: `config/routes.rb` (add `resources :roles`)
- Modify: `app/helpers/application_helper.rb` (RESOURCE_ICONS entry)
- Modify: `app/views/layouts/application.html.haml` (Roles link in Admin section)
- Modify: `app/assets/stylesheets/application.scss` (role badges)

**Interfaces:**
- Consumes: `Role`, `Permission::CATALOG`, `require_admin` (Tasks 1–4).
- Produces: routes `roles_path`, `role_path(role)`, `new_role_path`, `edit_role_path(role)`; SCSS classes `.badge-role`, `.badge-staff`, `.badge-minimal`, `.badge-public-info` (`.badge-admin` exists).

- [ ] **Step 1: Route + icon + sidebar link**

`config/routes.rb` — after the `resources :users do ... end` block add:

```ruby
  resources :roles
```

`app/helpers/application_helper.rb` — in `RESOURCE_ICONS`, after the `"users" => "group",` line add:

```ruby
    "roles"         => "verified_user",
```

`app/views/layouts/application.html.haml` — in the Admin section, directly after the Users `%li.nav-item` block add:

```haml
            %li.nav-item
              = link_to roles_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'roles'}" do
                = resource_icon("roles")
                Roles
```

- [ ] **Step 2: Controller**

`app/controllers/roles_controller.rb`:

```ruby
class RolesController < ApplicationController
  # Entirely admin-only: role bundles decide who sees what, so even reading
  # them is an administration concern.
  before_action :require_admin
  before_action :set_role, only: %i[show edit update destroy]

  def index
    # Tiny table (a handful of roles) — eager-load and count in Ruby rather
    # than a grouped select, which trips up relation#empty? in the view.
    @roles = Role.includes(:parent_roles, :users).order(:name)
  end

  def show
  end

  def new
    @role = Role.new
  end

  def create
    @role = Role.new(role_params)

    if @role.save
      redirect_to @role, notice: "Role was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @role.errors.add(:base, e.record.errors.full_messages.to_sentence)
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @role.update(role_params)
      redirect_to @role, notice: "Role was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    # parent_role_ids= on a persisted record saves edges immediately; a cycle
    # or locked-role rejection surfaces as RecordInvalid, not a false update.
    @role.errors.add(:base, e.record.errors.full_messages.to_sentence)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @role.destroy
      redirect_to roles_path, notice: "Role was successfully deleted."
    else
      redirect_to @role, alert: @role.errors.full_messages.to_sentence
    end
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def role_params
    permitted = params.require(:role).permit(:name, :description, permission_keys: [], parent_role_ids: [])
    permitted[:permission_keys] = Array(permitted[:permission_keys]).reject(&:blank?) if permitted.key?(:permission_keys)
    permitted[:parent_role_ids] = Array(permitted[:parent_role_ids]).reject(&:blank?) if permitted.key?(:parent_role_ids)
    permitted
  end
end
```

- [ ] **Step 3: Views**

`app/views/roles/index.html.haml`:

```haml
.card{"data-controller" => "datatable"}
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Roles
      - if current_user.admin?
        = link_to "New Role", new_role_path, class: "btn btn-primary btn-sm"
    .table-responsive
      %table.table.table-hover.mb-0{"data-datatable-target" => "table"}
        %thead
          %tr
            %th Role
            %th Description
            %th Inherits From
            %th.text-center Permissions
            %th.text-center Users
            %th Actions
        %tbody
          - @roles.each do |role|
            %tr
              %td
                %span.badge{class: "badge-role badge-#{role.name.dasherize}"}= role.display_name
                - if role.locked?
                  %span.material-symbols.ms-1{style: "font-size: 14px; vertical-align: middle; opacity: 0.6"} lock
              %td= role.description
              %td
                - if role.parent_roles.any?
                  = role.parent_roles.map(&:display_name).join(", ")
                - else
                  %span.text-muted —
              %td.text-center= role.effective_permission_keys.size
              %td.text-center= role.users.size
              %td
                = link_to role, class: "btn-ghost btn-ghost-primary me-1", title: "Show" do
                  %span.material-symbols{style: "font-size: 18px"} visibility
                - unless role.locked?
                  = link_to edit_role_path(role), class: "btn-ghost btn-ghost-secondary me-1", title: "Edit" do
                    %span.material-symbols{style: "font-size: 18px"} edit
                  = link_to role, data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "btn-ghost btn-ghost-danger", title: "Delete" do
                    %span.material-symbols{style: "font-size: 18px"} delete
          - if @roles.empty?
            %tr
              %td.text-muted.text-center{colspan: 6} No roles found.
```

`app/views/roles/show.html.haml`:

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1
    = @role.display_name
    - if @role.locked?
      %span.material-symbols.ms-2{style: "font-size: 24px; vertical-align: middle; opacity: 0.6"} lock
  .d-flex.gap-2
    - unless @role.locked?
      = link_to "Edit", edit_role_path(@role), class: "btn btn-outline-secondary"
    = link_to "Back", roles_path, class: "btn btn-outline-primary"

.card
  .card-body
    .detail-section
      %dl.dl-fields.row.mb-0
        %dt.col-sm-3 Name
        %dd.col-sm-9
          %span.badge{class: "badge-role badge-#{@role.name.dasherize}"}= @role.display_name

        %dt.col-sm-3 Description
        %dd.col-sm-9= @role.description.presence || "—"

        %dt.col-sm-3 Inherits from
        %dd.col-sm-9
          - if @role.parent_roles.any?
            - @role.parent_roles.each do |parent|
              = link_to parent.display_name, parent, class: "me-2"
          - else
            %span.text-muted — none —

        %dt.col-sm-3 Users
        %dd.col-sm-9= @role.users.count

    .detail-section
      %h6.section-title Effective Permissions
      -# Own grants plus inherited, labeled with where each came from, so
      -# "what can this role actually do?" is answerable at a glance.
      %table.table.mb-0
        %thead
          %tr
            %th Permission
            %th Description
            %th Source
        %tbody
          - own = @role.permission_keys
          - @role.effective_permission_keys.sort.each do |key|
            %tr
              %td
                %code= key
              %td.text-muted= Permission.label(key)
              %td
                - if own.include?(key)
                  own
                - else
                  - source = @role.parent_roles.find { |p| p.effective_permission_keys.include?(key) }
                  inherited via #{source&.display_name}
```

`app/views/roles/_form.html.haml`:

```haml
= form_with(model: role, class: "needs-validation") do |f|
  - if role.errors.any?
    .alert.alert-danger
      %h5.alert-heading
        = pluralize(role.errors.count, "error")
        prohibited this role from being saved:
      %ul.mb-0
        - role.errors.full_messages.each do |message|
          %li= message

  .mb-3
    = f.label :name, class: "form-label"
    .input-group
      %span.input-group-text
        %span.material-symbols verified_user
      = f.text_field :name, class: "form-control #{'is-invalid' if role.errors[:name].any?}", placeholder: "e.g. ta_helper"
      - if role.errors[:name].any?
        .invalid-feedback= role.errors[:name].first
    .form-text Underscore slug; shown titleized (e.g. ta_helper → “Ta Helper”).

  .mb-3
    = f.label :description, class: "form-label"
    = f.text_field :description, class: "form-control"

  .mb-3
    %label.form-label Permissions
    - Permission::CATALOG.each do |key, label|
      .form-check
        = check_box_tag "role[permission_keys][]", key, role.permission_keys.include?(key), id: "perm_#{key.parameterize(separator: '_')}", class: "form-check-input"
        %label.form-check-label{for: "perm_#{key.parameterize(separator: '_')}"}
          %code= key
          %span.text-muted.ms-1= label
    = hidden_field_tag "role[permission_keys][]", ""
    .form-text Effective permissions also include everything inherited below.

  .mb-3
    %label.form-label Inherits from
    - Role.where.not(id: role.id).order(:name).each do |other|
      .form-check
        = check_box_tag "role[parent_role_ids][]", other.id, role.parent_role_ids.include?(other.id), id: "parent_#{other.id}", class: "form-check-input"
        %label.form-check-label{for: "parent_#{other.id}"}= other.display_name
    = hidden_field_tag "role[parent_role_ids][]", ""
    .form-text This role gains all permissions of the checked roles (cycles are rejected).

  = f.submit class: "btn btn-primary"
```

`app/views/roles/new.html.haml`:

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1 New Role
  = link_to "Back", roles_path, class: "btn btn-outline-primary"

.card
  .card-body
    = render "form", role: @role
```

`app/views/roles/edit.html.haml` (Back goes to the show page per project convention):

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1 Edit Role
  = link_to "Back", role_path(@role), class: "btn btn-outline-primary"

.card
  .card-body
    = render "form", role: @role
```

- [ ] **Step 4: Badges**

In `app/assets/stylesheets/application.scss`, find the frosted-badge block (`.badge-admin` at ~line 182). Replace the `.badge-editor` and `.badge-viewer` lines (those roles no longer exist) with:

```scss
// Role badges. .badge-role is the generic fallback so roles created later in
// the admin UI look sane with no deploy; seeded-role classes below override it
// (defined after, same specificity).
.badge-role        { background-color: rgba(150, 150, 150, 0.18); color: rgba(210, 210, 210, 0.8); border: 1px solid rgba(150, 150, 150, 0.35); }
.badge-staff       { background-color: rgba($primary, 0.2);   color: $primary;    border: 1px solid rgba($primary, 0.4); }
.badge-minimal     { background-color: rgba($info, 0.2);      color: $info;       border: 1px solid rgba($info, 0.4); }
.badge-public-info { background-color: rgba($success, 0.2);   color: $success;    border: 1px solid rgba($success, 0.4); }
```

(`.badge-admin` stays as-is; note it must remain AFTER `.badge-role` in the file — it already is.)

Run: `bin/rails dartsass:build`
Expected: compiles without error.

- [ ] **Step 5: Verify + backlog check**

With `AUTO_LOGIN=1 bin/rails server`: `/roles` lists 4 roles with user counts; admin row shows the lock and no edit/delete; create a `ta_helper` role with `students.read_minimal` + inherit `public_info` → show page lists 2 effective permissions (one own, one inherited); edit it to inherit `staff` as well; delete it. Attempt to edit `admin` via URL `/roles/<admin id>/edit` → form submits but save is rejected ("This role is locked...").

Per CLAUDE.md backlog rule: this adds an entity show page — open `docs/backlog.md`, check the entity→report cross-link items. Roles have no reports; consciously skip and note nothing to do.

Run: `bin/rails test test/controllers`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
hg add app/controllers/roles_controller.rb app/views/roles
hg commit app/controllers/roles_controller.rb app/views/roles config/routes.rb app/helpers/application_helper.rb app/views/layouts/application.html.haml app/assets/stylesheets/application.scss -m "Add admin CRUD for roles

Re-bundling permissions must be an admin action, not a deploy — that was
the point of putting roles in the DB. The form is a checkbox grid over the
frozen permission catalog plus inherits-from checkboxes (cycle-rejected);
the show page lists effective permissions labeled own vs inherited so
\"what can this role do?\" has a one-glance answer. The locked admin role
is view-only. badge-editor/viewer die with their roles; badge-role is the
generic fallback so UI-created roles render sanely without new SCSS.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Advisorship UI — advisor card on student page, advisees card on staff page

**Files:**
- Create: `app/controllers/advisorships_controller.rb`
- Create: `app/views/students/_advisors_card.html.haml`
- Create: `app/views/staffs/_advisees_card.html.haml`
- Modify: `config/routes.rb`, `app/views/students/show.html.haml`, `app/views/staffs/show.html.haml`

**Interfaces:**
- Consumes: `Advisorship`, `Student#advisorships`, `Staff#current_advisees` (Task 3), `require_admin` (Task 4).
- Produces: routes `advisorships_path` (POST), `advisorship_path(a)` (PATCH end / DELETE remove).

- [ ] **Step 1: Routes + controller**

`config/routes.rb` — after `resources :roles` add:

```ruby
  resources :advisorships, only: %i[create update destroy]
```

`app/controllers/advisorships_controller.rb`:

```ruby
class AdvisorshipsController < ApplicationController
  before_action :require_admin
  before_action :set_advisorship, only: %i[update destroy]

  def create
    advisorship = Advisorship.new(advisorship_params)
    if advisorship.save
      redirect_to advisorship.student, notice: "Advisor added."
    else
      redirect_to advisorship.student || students_path, alert: advisorship.errors.full_messages.to_sentence
    end
  end

  # The only edit is ending: sets ended_on, preserving history. Reassignment
  # is end + create, never destroy.
  def update
    if @advisorship.update(ended_on: Date.current)
      redirect_to @advisorship.student, notice: "Advisorship ended."
    else
      redirect_to @advisorship.student, alert: @advisorship.errors.full_messages.to_sentence
    end
  end

  # Destroy is for mistakes only (wrong person clicked in).
  def destroy
    student = @advisorship.student
    @advisorship.destroy!
    redirect_to student, notice: "Advisorship removed."
  end

  private

  def set_advisorship
    @advisorship = Advisorship.find(params[:id])
  end

  def advisorship_params
    params.require(:advisorship).permit(:student_id, :staff_id, :started_on, :note)
  end
end
```

- [ ] **Step 2: Advisor card on the student page**

`app/views/students/_advisors_card.html.haml`:

```haml
.card.mt-3
  .card-body.p-3
    %h5.card-title.mb-3.fw-semibold.d-flex.align-items-center
      %span.material-symbols.resource-icon.me-2 supervisor_account
      Advisors
    - if student.advisorships.any?
      .table-responsive
        %table.table.table-hover.mb-0
          %thead
            %tr
              %th Advisor
              %th Started
              %th Ended
              %th Note
              - if current_user.admin?
                %th Actions
          %tbody
            - student.advisorships.order(ended_on: :desc, started_on: :desc).each do |advisorship|
              %tr
                %td= link_to advisorship.staff.display_name_th, advisorship.staff
                %td= advisorship.started_on
                %td
                  - if advisorship.current?
                    %span.badge.badge-active Current
                  - else
                    = advisorship.ended_on
                %td.text-muted= advisorship.note
                - if current_user.admin?
                  %td
                    - if advisorship.current?
                      = button_to advisorship_path(advisorship), method: :patch, class: "btn-ghost btn-ghost-secondary me-1", title: "End advisorship", form: { data: { turbo_confirm: "End this advisorship?" }, class: "d-inline" } do
                        %span.material-symbols{style: "font-size: 18px"} event_busy
                    = button_to advisorship_path(advisorship), method: :delete, class: "btn-ghost btn-ghost-danger", title: "Delete (mistake only)", form: { data: { turbo_confirm: "Delete this record entirely? Use End for normal reassignment." }, class: "d-inline" } do
                      %span.material-symbols{style: "font-size: 18px"} delete
    - else
      %p.text-muted.mb-0 No advisor recorded.
    - if current_user.admin?
      = form_with(model: Advisorship.new, url: advisorships_path, class: "d-flex align-items-end gap-2 mt-3 flex-wrap") do |f|
        = f.hidden_field :student_id, value: student.id
        .flex-grow-1{style: "min-width: 220px; max-width: 340px"}
          %label.form-label.small.text-muted Staff
          = f.select :staff_id, options_for_select(Staff.order(:first_name).map { |s| [s.display_name_th, s.id] }), { include_blank: "— select —" }, class: "form-select form-select-sm", data: { controller: "select2" }
        .flex-grow-0
          %label.form-label.small.text-muted Started on
          = f.date_field :started_on, value: Date.current, class: "form-control form-control-sm"
        = f.submit "Add Advisor", class: "btn btn-primary btn-sm"
```

In `app/views/students/show.html.haml`, directly after the first `.card` block (the main details card, before the Schedule card's `- if @full_access && @schedule_semesters&.any?` line) insert:

```haml
- if @full_access
  = render "advisors_card", student: @student
```

- [ ] **Step 3: Advisees card on the staff page**

`app/views/staffs/_advisees_card.html.haml`:

```haml
.card.mt-3
  .card-body.p-3
    %h5.card-title.mb-3.fw-semibold.d-flex.align-items-center
      %span.material-symbols.resource-icon.me-2 supervisor_account
      Current Advisees
    - if staff.current_advisees.any?
      .table-responsive
        %table.table.table-hover.mb-0
          %thead
            %tr
              %th Student ID
              %th Name
              %th Program
              %th Admission Year (B.E.)
          %tbody
            - staff.current_advisees.includes(program: :program_group).order(:student_id).each do |student|
              %tr
                %td= student.student_id
                %td= link_to student.display_name, student
                %td= student.program&.name_en
                %td= student.admission_year_be
    - else
      %p.text-muted.mb-0 No current advisees.
```

In `app/views/staffs/show.html.haml`: read the file, find the last card block, and append at the bottom (the card reveals student names, so it needs the roster permission):

```haml
- if current_user.can?("students.read_minimal")
  = render "advisees_card", staff: @staff
```

- [ ] **Step 4: Verify**

With `AUTO_LOGIN=1 bin/rails server`: on a student page add an advisor (appears with Current badge), check the staff page lists the advisee, End it (badge → date), re-add, Delete the ended row. Backlog rule: entity show pages changed (student, staff) — the two cards cross-link student↔staff pages, which satisfies the cross-link item; note it.

Run: `bin/rails test test/controllers test/models`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg add app/controllers/advisorships_controller.rb app/views/students/_advisors_card.html.haml app/views/staffs/_advisees_card.html.haml
hg commit app/controllers/advisorships_controller.rb app/views/students/_advisors_card.html.haml app/views/staffs/_advisees_card.html.haml config/routes.rb app/views/students/show.html.haml app/views/staffs/show.html.haml -m "Add advisorship management to student and staff pages

Recording an advisorship IS how someone becomes an advisor (the scoped
permission activates on data, not on a role flip), so admins need a
friction-free place to do it: an inline card on the student page with
add/end/delete, and a read-only advisees card on the staff page. End
preserves history (sets ended_on); Delete exists for mis-clicks only.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: AdvisorshipImporter

**Files:**
- Create: `app/services/importers/advisorship_importer.rb`
- Modify: `app/models/data_import.rb` (IMPORTERS entry)

**Interfaces:**
- Consumes: `Importers::Base` contract (`attribute_definitions`, `find_existing_record`, `build_new_record`, `transform_attributes`, `unique_key_fields`), `Advisorship` (Task 3).
- Produces: `Importers::AdvisorshipImporter`; `DataImport::IMPORTERS["Advisorship"]`.

- [ ] **Step 1: Importer**

First skim `app/services/importers/grade_importer.rb` for how it resolves students — mirror its lookup normalization if it differs from below.

`app/services/importers/advisorship_importer.rb`:

```ruby
module Importers
  # Bulk-loads advisor↔advisee assignments (CSV/Excel: one row per pairing).
  # Rows whose student or staff cannot be resolved are SKIPPED (blank unique
  # key), not errored — re-run after fixing the source data and the found
  # rows upsert idempotently against the current advisorship for the pair.
  class AdvisorshipImporter < Base
    def self.attribute_definitions
      [
        { attribute: :student_id, label: "Student ID", required: true,
          aliases: ["student id", "student_id", "id", "รหัสนิสิต", "เลขประจำตัวนิสิต"] },
        { attribute: :staff_name, label: "Advisor", required: true,
          aliases: ["advisor", "advisor name", "staff", "อาจารย์ที่ปรึกษา", "ที่ปรึกษา"],
          help: "Matched against staff initials (e.g. NNN), then English name, then Thai name." },
        { attribute: :started_on, label: "Start Date", required: false,
          aliases: ["start", "start date", "started on", "วันที่เริ่ม"],
          help: "Defaults to today when blank." }
      ]
    end

    private

    def transform_attributes(attrs)
      # Roo reads numeric cells as floats — strip the ".0" before lookup.
      student = Student.find_by(student_id: attrs[:student_id].to_s.gsub(/\.0\z/, ""))
      staff = find_staff(attrs[:staff_name].to_s.strip)

      {
        student_id: student&.id,
        staff_id: staff&.id,
        started_on: attrs[:started_on].presence || Date.current
      }
    end

    def find_staff(value)
      return nil if value.blank?
      Staff.find_by(initials: value.upcase) ||
        Staff.all.find { |s| s.display_name == value || s.display_name_th == value }
    end

    def find_existing_record(attrs)
      Advisorship.current.find_by(student_id: attrs[:student_id], staff_id: attrs[:staff_id])
    end

    def build_new_record(attrs)
      Advisorship.new(attrs)
    end

    def unique_key_fields
      [:student_id, :staff_id]
    end
  end
end
```

- [ ] **Step 2: Register**

`app/models/data_import.rb` — in `IMPORTERS` add:

```ruby
    "Advisorship" => "Importers::AdvisorshipImporter"
```

(mind the trailing comma on the previous line).

- [ ] **Step 3: Verify**

```bash
bin/rails runner '
staff = Staff.where.not(initials: nil).first or raise "need staff with initials"
student = Student.first
csv = "student_id,advisor\n#{student.student_id},#{staff.initials}\n999INVALID,#{staff.initials}\n"
path = "/tmp/claude-1000/-home-dae-cp-api/ba804377-c266-4174-83a1-9d9b3d4a03bb/scratchpad/advisors_test.csv"
FileUtils.mkdir_p(File.dirname(path)); File.write(path, csv)
di = DataImport.new(target_type: "Advisorship", mode: "upsert", state: "pending", user: User.first, skip_failures: true)
di.file.attach(io: File.open(path), filename: "advisors_test.csv", content_type: "text/csv")
di.column_mapping = Importers::AdvisorshipImporter.auto_map(["student_id", "advisor"])
di.save!
Importers::AdvisorshipImporter.new(di).call
di.reload
puts "state=#{di.state} created=#{di.created_count} skipped=#{di.skipped_count}"
Advisorship.where(student: Student.find_by(student_id: student.student_id)).destroy_all
di.destroy!'
```

Expected: `state=completed created=1 skipped=1` (unknown student skipped, real row created; both cleaned up after).

Run: `bin/rails test test/models/data_import_test.rb` (if it exists — `ls test/models/`)
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
hg add app/services/importers/advisorship_importer.rb
hg commit app/services/importers/advisorship_importer.rb app/models/data_import.rb -m "Add advisorship importer

The real advisor list lives in a departmental spreadsheet; hand-entering
a hundred pairings through the student-page card doesn't scale. This
reuses the standard import flow (upload → mapping → execute) with staff
matched by initials, then English, then Thai name, and unresolvable rows
skipped for a fix-and-rerun cycle rather than failing the batch.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: LINE tool pipeline gates (1: filtered definitions, 2: executor re-check, 3: in-tool scoping)

**Files:**
- Modify: `app/services/line/tool_registry.rb`
- Modify: `config/initializers/line_tools.rb`
- Modify: `app/services/line/tool_executor.rb`
- Modify: `app/services/line/llm_service.rb` (one line)
- Modify: `app/services/line/tools/student_lookup_tool.rb`, `student_grades_tool.rb`, `search_tool.rb`
- Modify: `test/services/line/tool_executor_test.rb`, `test/services/line/llm_service_test.rb` (register-call signatures)

**Interfaces:**
- Consumes: `User#can?`, `#can_view_student_fully?`, `#can_view_grades?` (Tasks 2–3).
- Produces: `ToolRegistry.register(name, definition:, handler:, permission:)` (keyword now required), `ToolRegistry.definitions(user: nil)` (nil user → unfiltered, for the admin playground and offline eval harness), `ToolRegistry.required_permission_for(name)`.

- [ ] **Step 1: Registry**

In `app/services/line/tool_registry.rb` replace `register`, `definitions`, and add `required_permission_for`:

```ruby
    def register(name, definition:, handler:, permission:)
      registry[name] = { definition: definition, handler: handler, permission: permission }
    end

    # OpenAI-format tools array, filtered to what this user's role permits —
    # the LLM never sees tools the user can't call (gate 1: keeps weak local
    # models from attempting doomed calls and the prompt small). nil user =
    # unfiltered: the admin web playground and the offline eval harness.
    def definitions(user: nil)
      registry.filter_map do |name, entry|
        next if user && !user.can?(entry[:permission])
        {
          type: "function",
          function: { name: name }.merge(entry[:definition])
        }
      end
    end

    # Gate 2 lookup (see ToolExecutor): the permission a tool call must hold.
    def required_permission_for(name)
      registry.dig(name, :permission)
    end
```

Also update the usage comment at the top of the file (`.call(arguments, user: nil)` → mention `permission:`).

- [ ] **Step 2: Register permissions**

In `config/initializers/line_tools.rb` add a `permission:` line to every register call, per this table:

| Tool | permission |
|---|---|
| student_lookup | `"students.read_minimal"` |
| staff_lookup | `"courses.read"` |
| course_lookup | `"courses.read"` |
| course_offering_lookup | `"courses.read"` |
| search | `"courses.read"` |
| grade_distribution | `"grades.read"` |
| cohort_gpa | `"grades.read"` |
| cohort_ranking | `"grades.read"` |
| student_grades | `"students.read_minimal"` |
| course_enrollment | `"grades.read"` |
| semester_overview | `"courses.read"` |
| room_schedule | `"courses.read"` |
| missing_enrollments | `"grades.read"` |

(`student_grades` is deliberately minimal at the registry so advisee-scoped users keep the tool; the per-student check is gate 3. Aggregate tools are `grades.read` outright — aggregates leak grades.)

Example of the first entry:

```ruby
  Line::ToolRegistry.register(
    "student_lookup",
    definition: Line::Tools::StudentLookupTool::DEFINITION,
    handler: Line::Tools::StudentLookupTool,
    permission: "students.read_minimal"
  )
```

- [ ] **Step 3: Executor re-check (gate 2)**

In `app/services/line/tool_executor.rb` `self.invoke`, insert between the `unless handler ... end` block and the `arguments = ...` line:

```ruby
    # Gate 2: the definitions filter (gate 1) only controls what the LLM is
    # TOLD exists. Local models hallucinate un-offered tools, and replayed
    # chat history advertises tools the user could call before a role edit.
    permission = Line::ToolRegistry.required_permission_for(name)
    if user && permission && !user.can?(permission)
      ApiEvent.log(service: "llm", action: "tool_call", severity: "warning",
                   message: "Denied tool: #{name}", details: { tool: name, user_id: user.id, permission: permission })
      return "Error: you are not authorized to use '#{name}'."
    end
```

- [ ] **Step 4: Filter definitions per user (gate 1)**

In `app/services/line/llm_service.rb` `#call`, change:

```ruby
    tools = Line::ToolRegistry.definitions
```

to:

```ruby
    tools = Line::ToolRegistry.definitions(user: @user)
```

- [ ] **Step 5: In-tool scoping (gate 3)**

`app/services/line/tools/student_lookup_tool.rb`:
- In `call`, change the two serialize call sites to pass the user: `scope.limit(limit).map { |s| serialize(s, user) }`.
- Replace `self.serialize` with:

```ruby
  def self.serialize(student, user)
    base = {
      student_id: student.student_id,
      name_th: student.full_name_th,
      name_en: student.full_name,
      program: "#{student.program.program_group.code} (#{student.program.year_started_be})",
      admission_year: student.admission_year_be,
      cohort: student.program.program_group.cohort_label(student.admission_year_be)
    }
    # Field-level tiering mirrors the web UI: status is read_full territory,
    # GPA/credits are grade data. nil user (admin playground/eval) sees all.
    if user.nil? || user.can_view_student_fully?(student)
      base[:status] = student.status
    end
    if user.nil? || user.can_view_grades?(student)
      base[:gpa] = student.gpa
      base[:total_credits] = student.total_credits
    end
    base
  end
  private_class_method :serialize
```

`app/services/line/tools/student_grades_tool.rb` — in `call`, directly after `student = students.first`, insert:

```ruby
    # Gate 3: the only place advisee scope CAN be enforced — it depends on
    # which student the arguments resolved to.
    unless user.nil? || user.can_view_grades?(student)
      return { error: "You are not authorized to view this student's grades." }.to_json
    end
```

`app/services/line/tools/search_tool.rb` — in `call`, replace the `students = search_students(query, limit)` line with:

```ruby
    students = if user.nil? || user.can?("students.read_minimal")
      search_students(query, limit)
    else
      { results: [], total: 0 }
    end
```

`search_students` emits `status` per student (verified) — tier it. Change the call site to pass the user (`search_students(query, limit, user)`), the signature to `def self.search_students(query, limit, user)`, and the result map block to:

```ruby
    results = scope.order(:student_id).limit(limit).map do |s|
      entry = {
        student_id: s.student_id,
        name_th: s.full_name_th,
        name_en: s.full_name,
        program: "#{s.program.program_group.code} (#{s.program.year_started_be})"
      }
      entry[:status] = s.status if user.nil? || user.can_view_student_fully?(s)
      entry
    end
```

- [ ] **Step 6: Fix test register calls, run LINE tests**

Run: `grep -rn "ToolRegistry.register" test/`
Add `permission: "courses.read"` to each dummy registration.

Run: `bin/rails test test/services/line`
Expected: PASS.

Verify filtering end-to-end:

```bash
bin/rails runner '
minimal = User.new(role: Role.find_by!(name: "minimal"))
staff = User.new(role: Role.find_by!(name: "staff"))
names = ->(u) { Line::ToolRegistry.definitions(user: u).map { |d| d[:function][:name] }.sort }
puts "minimal: #{names.call(minimal).join(", ")}"
puts "staff sees #{names.call(staff).size}, nil sees #{Line::ToolRegistry.definitions.size}"
raise "minimal must not see grades tools" if names.call(minimal).include?("student_grades") == false || names.call(minimal).include?("cohort_gpa")
puts "definitions filtering OK"'
```

Expected: minimal lists the courses.read + students.read_minimal tools (incl. `student_grades`, excl. `cohort_gpa`/`grade_distribution`/`cohort_ranking`/`course_enrollment`/`missing_enrollments`); staff sees all 13; `definitions filtering OK`.

- [ ] **Step 7: Commit**

```bash
hg commit app/services/line/tool_registry.rb config/initializers/line_tools.rb app/services/line/tool_executor.rb app/services/line/llm_service.rb app/services/line/tools/student_lookup_tool.rb app/services/line/tools/student_grades_tool.rb app/services/line/tools/search_tool.rb test/services/line/tool_executor_test.rb test/services/line/llm_service_test.rb -m "Gate LINE tools by permission at three layers

Linking used to BE authorization — every linked user was trusted staff.
Public-info students created via quick-link break that equivalence, so the
tool pipeline gets layered gates: definitions filtered by role (the LLM
never sees forbidden tools), an executor re-check (local models hallucinate
un-offered tools; replayed history advertises pre-downgrade ones), and
in-tool per-student checks — the only layer that can enforce advisee scope,
since it depends on the resolved arguments. student_lookup and search now
tier fields (status behind read_full, GPA behind grades) exactly like the
web UI.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation, full-suite green, smoke matrix

**Files:**
- Modify: `CLAUDE.md` (Authentication section, badge list, Data Model Conventions, Import System)
- Modify: `docs/llm-data-query.md` (tool permission note)
- Modify: any test fixed along the way

**Interfaces:** none produced; this task closes the loop.

- [ ] **Step 1: CLAUDE.md**

Replace the `## Authentication` section body with:

```markdown
- Session-based login with `has_secure_password` (bcrypt)
- `ApplicationController` provides `current_user`, `logged_in?`, and `require_login` (applied to all controllers by default)
- Controllers that allow unauthenticated access must `skip_before_action :require_login`
- Login page uses a separate `auth` layout (no sidebar)

## Roles & Permissions

- **Permission catalog is code** (`Permission::CATALOG`, 6 keys); **roles are DB rows** (`Role`) bundling keys, with DAG inheritance via `role_inheritances`. Admin CRUD at `/roles`. Seeded roles: `admin` (locked), `staff`, `minimal`, `public_info`; new users default to `public_info`.
- **Check permissions via `user.can?("key")`**, writes via `require_admin`, reads via `require_permission("key")` in controllers (both live in `ApplicationController` — do NOT re-define per controller).
- **Advisor is data, not a role**: `advisees.read_full` activates only through `advisorships` rows (history-preserving join of student↔staff; `users.staff_id` links the account). Scoped checks go through `user.can_view_student_fully?(student)` / `user.can_view_grades?(student)` — never re-derive advisee logic.
- **students.read_minimal limits fields, not rows** (full roster browse, minimal columns). `students.read_full` does NOT include grade values — those are `grades.read` / advisee scope.
- **LINE tools declare `permission:`** at registration; definitions are filtered per user, the executor re-checks, and student-scoped tools check per student (see `docs/llm-data-query.md`).
- **Reports carry a permission key** in `Reports::Catalog` (`access:`); the hub filters by `current_user.can?`.
- Spec: `docs/superpowers/specs/2026-07-22-roles-permissions-design.md`.
```

In `## UI Component Conventions` badge list: remove `.badge-editor`, `.badge-viewer`; add `.badge-role` (generic fallback), `.badge-staff`, `.badge-minimal`, `.badge-public-info`.

In `## Data Model Conventions` add a bullet:

```markdown
- **Advisorships**: `advisorships(student_id, staff_id, started_on, ended_on, note)` — current = `ended_on IS NULL`; co-advisors legal; same pair active once. Managed from the student show page card; bulk via `Importers::AdvisorshipImporter`.
```

In `## Import System`, adding-a-new-importer bullet stays valid; no change needed beyond the Advisorship mention above.

- [ ] **Step 2: docs/llm-data-query.md**

Read the doc; add a short subsection near the tool-registration docs:

```markdown
## Tool permissions

Every `ToolRegistry.register` call declares `permission:` (a `Permission::CATALOG` key). Three gates apply: `definitions(user:)` filters what the LLM is offered; `ToolExecutor` re-checks by name (hallucinated/history-replayed calls); student-scoped tools (`student_grades`, `student_lookup`, `search`) additionally check `can_view_grades?` / `can_view_student_fully?` per resolved student. `nil` user (admin playground, eval harness) bypasses filtering.
```

- [ ] **Step 3: Full suite + system tests**

Run: `bin/rails test`
Expected: PASS.

Run: `bin/rails test:system`
Expected: PASS. System tests log in as fixture users whose roles changed to `staff` — same effective read access as before, so failures indicate a real regression; fix forward using the Task 2 mapping (fixture users keep read-everything except admin pages).

- [ ] **Step 4: Smoke matrix**

Create four users (or reuse fixtures via console) — one per seeded role — and walk this matrix with `AUTO_LOGIN=<id>`:

| Page | public_info | minimal | staff | admin |
|---|---|---|---|---|
| `/courses`, `/semesters`, `/program_groups` | ✓ | ✓ | ✓ | ✓ |
| `/students` (roster) | redirect | ✓ minimal columns | ✓ full | ✓ |
| `/students/:id` | redirect | identity+program+year only | full | full |
| `/grades`, `/reports` grade reports | redirect | redirect | ✓ | ✓ |
| `/scrapes`, `/data_imports`, `/roles` | redirect | redirect | redirect | ✓ |

Also verify the advisee path: give a `minimal`-role user a `staff_id` whose Staff has a current advisorship; add `advisees.read_full` to a scratch role inheriting `minimal`; their advisee's show page renders fully (incl. grades), other students stay minimal. Delete scratch users/roles after.

- [ ] **Step 5: Commit**

```bash
hg commit CLAUDE.md docs/llm-data-query.md -m "Document the roles & permissions system

Future sessions need the load-bearing rules in CLAUDE.md: permissions are
code, roles are data, advisor is data not a role, minimal limits fields
not rows, and where the enforcement points live (require_permission,
composite helpers, LINE tool gates, report access keys).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Include any test files fixed in Step 3 in that commit's file list, or commit them separately with their own message.)

---

## Post-plan follow-ups (explicitly OUT of these tasks)

- **New tests**: per project convention, discuss scope with dae first (spec §Testing plan lists the intended coverage: Role DAG model tests, role×controller access matrix, LINE gate tests, tiered-show system tests).
- **Production deploy**: separate step, includes running the migrations and re-checking `config/llm.yml` handling per CLAUDE.md deploy notes.
- **Real advisor data import** via the new importer once dae provides the spreadsheet.
