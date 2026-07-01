# Course ↔ Program M:N Re-model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Course belongs_to :program` (1:N) with a proper many-to-many through a `ProgramCourse` join model — backfilling existing links and dropping `courses.program_id` — with no user-facing regression.

**Architecture:** Three tasks. **Task 1** is purely additive (create the join table + model + the Course associations that don't clash with the existing `belongs_to`), so the suite stays green. **Task 2** is the atomic cutover (backfill, drop the column, swap associations/importer/controller/views/fixtures and fix the now-broken existing tests) in one green commit. **Task 3** adds new behavioral tests. This is Approach A from the spec.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, MySQL 8, Minitest + fixtures, HAML/Turbo, Mercurial (hg).

**Spec:** `docs/superpowers/specs/2026-06-30-course-program-m2m-remodel-design.md`

## Global Constraints

- **VCS is Mercurial (hg), NOT git.** Commit with `hg commit <explicit paths> -m "..."`; always name explicit files (the repo may carry unrelated dirty changes). Every commit message's **first line leads with WHY**.
- **MySQL:** a foreign key must be dropped **before** its column.
- **B.E. years:** DB stores Buddhist Era; the importer's existing CE→BE (`+543`) logic is untouched.
- **No "course must have a program" invariant** — a course may have 0, 1, or many programs.
- **`remark` on the join is local** — never overwritten by the future sync.
- **Non-regression is the bar:** after each task, `bin/rails test` and (for Task 2+) `bin/rails test:system` must pass.
- Migrations update `db/schema.rb`; include it in the same commit. The test DB auto-syncs via `maintain_test_schema`.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `db/migrate/*_create_program_courses.rb` | create | join table + unique index |
| `db/migrate/*_backfill_and_drop_course_program_id.rb` | create | backfill links, drop `courses.program_id` |
| `app/models/program_course.rb` | create | the join model |
| `app/models/course.rb` | modify | swap `belongs_to` → `has_many :through`; importer link hook |
| `app/models/program.rb` | modify | `courses` through join; `dependent: :destroy` on join |
| `app/models/program_group.rb` | modify | `courses` via nested through |
| `app/services/importers/course_importer.rb` | modify | link program via join instead of `program_id` |
| `app/controllers/courses_controller.rb` | modify | `program_ids` handling; `includes(:programs)` |
| `app/views/courses/_form.html.haml` | modify | single-program `select_tag` |
| `app/views/courses/show.html.haml` | modify | list `programs` |
| `app/views/courses/index.html.haml` | modify | list `programs` |
| `test/fixtures/courses.yml` | modify | drop `program:` |
| `test/fixtures/program_courses.yml` | create | join fixtures (recreate today's 1:1) |
| `test/models/program_course_test.rb` | create | join model tests |
| `test/models/course_test.rb` | modify | swap `program`→`programs`; drop the invariant test |
| `test/models/program_test.rb` | modify | delete semantics + through |
| `test/system/courses_test.rb` | modify | `program`→`programs.first` |

---

### Task 1: Join table, `ProgramCourse` model, additive Course associations

**Files:**
- Create: `db/migrate/*_create_program_courses.rb`
- Create: `app/models/program_course.rb`
- Create: `test/fixtures/program_courses.yml`
- Create: `test/models/program_course_test.rb`
- Modify: `app/models/course.rb` (add associations only; keep `belongs_to :program`)
- Modify: `db/schema.rb` (via migration)

**Interfaces:**
- Produces: `ProgramCourse` with `belongs_to :program`, `belongs_to :course`, unique `(program_id, course_id)`. `Course#program_courses`, `Course#programs`. Fixtures `program_courses(:intro_cp, :senior_cp, :gened_cp)`.

- [ ] **Step 1: Generate the migration and replace its contents**

Run: `bin/rails g migration CreateProgramCourses`

Replace the generated file's contents with:

```ruby
class CreateProgramCourses < ActiveRecord::Migration[8.1]
  def change
    create_table :program_courses do |t|
      t.references :program, null: false, foreign_key: true
      t.references :course,  null: false, foreign_key: true
      t.string  :course_group_code   # nullable — populated later by ChulaBooster sync
      t.integer :course_type         # nullable — populated later by ChulaBooster sync
      t.string  :remark              # nullable — local annotation, sync never overwrites
      t.timestamps
    end
    add_index :program_courses, [:program_id, :course_id], unique: true
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `create_table(:program_courses)` succeeds; `db/schema.rb` now contains `create_table "program_courses"`.

- [ ] **Step 3: Create the `ProgramCourse` model**

Create `app/models/program_course.rb`:

```ruby
class ProgramCourse < ApplicationRecord
  belongs_to :program
  belongs_to :course

  validates :course_id, uniqueness: { scope: :program_id }
end
```

- [ ] **Step 4: Add the additive associations to `Course`** (keep `belongs_to :program` for now)

In `app/models/course.rb`, change the top association block from:

```ruby
class Course < ApplicationRecord
  belongs_to :program
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error
```

to:

```ruby
class Course < ApplicationRecord
  belongs_to :program
  has_many :program_courses, dependent: :destroy
  has_many :programs, through: :program_courses
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error
```

(`program` and `programs` do not clash; the suite stays green.)

- [ ] **Step 5: Create the join fixtures**

Create `test/fixtures/program_courses.yml` (mirrors the current 1:1 in `courses.yml`):

```yaml
intro_cp:
  program: cp_bachelor
  course: intro_computing

senior_cp:
  program: cp_bachelor
  course: senior_project

gened_cp:
  program: cp_bachelor
  course: gened_course
```

- [ ] **Step 6: Write the `ProgramCourse` model test**

Create `test/models/program_course_test.rb`:

```ruby
require "test_helper"

class ProgramCourseTest < ActiveSupport::TestCase
  test "valid fixture" do
    assert program_courses(:intro_cp).valid?
  end

  test "belongs to program and course" do
    pc = program_courses(:intro_cp)
    assert_equal programs(:cp_bachelor), pc.program
    assert_equal courses(:intro_computing), pc.course
  end

  test "same course cannot link to the same program twice" do
    dup = ProgramCourse.new(program: programs(:cp_bachelor), course: courses(:intro_computing))
    assert_not dup.valid?
    assert_includes dup.errors[:course_id], "has already been taken"
  end

  test "same course may link to a different program" do
    pc = ProgramCourse.new(program: programs(:cp_master), course: courses(:intro_computing))
    assert pc.valid?
  end
end
```

- [ ] **Step 7: Run the new test**

Run: `bin/rails test test/models/program_course_test.rb`
Expected: 4 runs, 0 failures.

- [ ] **Step 8: Run the full model suite (no regression)**

Run: `bin/rails test`
Expected: all pass (Course still `belongs_to :program`; nothing removed yet).

- [ ] **Step 9: Commit**

```bash
hg add app/models/program_course.rb test/fixtures/program_courses.yml test/models/program_course_test.rb db/migrate/*_create_program_courses.rb
hg commit db/migrate app/models/program_course.rb app/models/course.rb db/schema.rb test/fixtures/program_courses.yml test/models/program_course_test.rb \
  -m "Introduce ProgramCourse join so a course can belong to many programs; additive first step toward replacing the 1:N belongs_to (course still keeps program_id until the cutover)"
```

---

### Task 2: Cutover — backfill, drop `program_id`, swap associations/importer/controller/views/fixtures

This task must be committed as one green unit: it removes `belongs_to :program`, which breaks every consumer at once.

**Files:**
- Create: `db/migrate/*_backfill_and_drop_course_program_id.rb`
- Modify: `app/models/course.rb`, `app/models/program.rb`, `app/models/program_group.rb`
- Modify: `app/services/importers/course_importer.rb`
- Modify: `app/controllers/courses_controller.rb`
- Modify: `app/views/courses/_form.html.haml`, `show.html.haml`, `index.html.haml`
- Modify: `test/fixtures/courses.yml`, `test/models/course_test.rb`, `test/system/courses_test.rb`
- Modify: `db/schema.rb` (via migration)

**Interfaces:**
- Consumes: `Course#programs`, `Course#program_courses`, `ProgramCourse` (Task 1).
- Produces: `Course#import_program` (transient writer used by the importer). `Program#courses` (through join). `courses_controller` reads a scalar `params[:course][:program_id]` and assigns `@course.program_ids`.

- [ ] **Step 1: Generate the backfill/drop migration and replace its contents**

Run: `bin/rails g migration BackfillAndDropCourseProgramId`

Replace contents with:

```ruby
class BackfillAndDropCourseProgramId < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO program_courses (program_id, course_id, created_at, updated_at)
      SELECT program_id, id, NOW(), NOW() FROM courses
    SQL

    pc = select_value("SELECT COUNT(*) FROM program_courses").to_i
    c  = select_value("SELECT COUNT(*) FROM courses").to_i
    raise "backfill count mismatch (#{pc} != #{c}) — aborting" unless pc == c

    remove_foreign_key :courses, :programs   # MySQL: FK must go before the column
    remove_column :courses, :program_id      # also drops index_courses_on_program_id
  end

  def down
    add_column :courses, :program_id, :bigint
    execute <<~SQL
      UPDATE courses c
      JOIN program_courses pc ON pc.course_id = c.id
      SET c.program_id = pc.program_id
    SQL
    change_column_null :courses, :program_id, false
    add_index :courses, :program_id, name: "index_courses_on_program_id"
    add_foreign_key :courses, :programs
    execute "DELETE FROM program_courses"
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: backfill inserts one row per course (dev: 553), count check passes, `courses.program_id` dropped. `db/schema.rb` no longer shows `program_id` on `courses`.

- [ ] **Step 3: Finalize `Course` — drop `belongs_to`, add the importer link hook**

In `app/models/course.rb`, replace the top block from Task 1:

```ruby
class Course < ApplicationRecord
  belongs_to :program
  has_many :program_courses, dependent: :destroy
  has_many :programs, through: :program_courses
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error
```

with:

```ruby
class Course < ApplicationRecord
  has_many :program_courses, dependent: :destroy
  has_many :programs, through: :program_courses
  has_many :grades, dependent: :destroy
  has_many :course_offerings, dependent: :restrict_with_error

  # Transient: the CourseImporter sets this so a resolved program is linked
  # (additively) after the row is saved. Not a DB column.
  attr_accessor :import_program

  after_save :link_import_program, if: -> { import_program.present? }
```

Add this private method (place it with the other instance methods, before the final `end`):

```ruby
  private

  def link_import_program
    ProgramCourse.find_or_create_by!(program: import_program, course: self)
  end
```

(`auto_generated?` is public — keep it above `private`.)

- [ ] **Step 4: Finalize `Program` associations**

In `app/models/program.rb`, replace:

```ruby
  has_many :courses, dependent: :restrict_with_error
```

with:

```ruby
  has_many :program_courses, dependent: :destroy
  has_many :courses, through: :program_courses
```

(Destroying a program now destroys its join rows, not the courses. `has_many :students, dependent: :restrict_with_error` stays.)

- [ ] **Step 5: Finalize `ProgramGroup` associations**

In `app/models/program_group.rb`, replace:

```ruby
  has_many :courses, through: :programs
```

with:

```ruby
  has_many :program_courses, through: :programs
  has_many :courses, -> { distinct }, through: :program_courses
```

- [ ] **Step 6: Update the CourseImporter to link via the join**

In `app/services/importers/course_importer.rb`, replace the program block in `transform_attributes` (the `if attrs.key?(:program_name)` block, ~lines 112–119):

```ruby
      # Resolve program
      if attrs.key?(:program_name)
        program_value = attrs.delete(:program_name)
        if program_value.present?
          program = resolve_program(program_value)
          attrs[:program_id] = program&.id
        end
      end

      attrs
```

with:

```ruby
      # Resolve program and link it through the join (courses no longer carry program_id).
      if attrs.key?(:program_name)
        program_value = attrs.delete(:program_name)
        program = resolve_program(program_value) if program_value.present?
        if program
          existing = Course.find_by(course_no: attrs[:course_no], revision_year: attrs[:revision_year])
          if existing
            # Course already persisted (upsert/unchanged path): link immediately.
            ProgramCourse.find_or_create_by!(program: program, course: existing)
          else
            # New course: link after it is saved, via the transient hook.
            attrs[:import_program] = program
          end
        end
      end

      attrs
```

(`resolve_program`, `coerce_*` helpers are unchanged.)

- [ ] **Step 7: Update `courses_controller`**

In `app/controllers/courses_controller.rb`:

Change `index`:

```ruby
  def index
    @courses = Course.includes(:programs)
  end
```

Change `create`:

```ruby
  def create
    @course = Course.new(course_params)
    @course.program_ids = program_ids_param
    if @course.save
      redirect_to @course, notice: "Course was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end
```

Change `update`:

```ruby
  def update
    @course.assign_attributes(course_params)
    @course.program_ids = program_ids_param
    if @course.save
      redirect_to @course, notice: "Course was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
```

In `course_params`, remove `:program_id` from the permit list:

```ruby
  def course_params
    params.require(:course).permit(
      :name, :name_th, :name_abbr, :course_group, :course_no, :revision_year,
      :is_gened, :department_code, :credits,
      :l_credits, :nl_credits, :l_hours, :nl_hours, :s_hours, :is_thesis
    )
  end
```

Add a private helper (next to `course_params`):

```ruby
  def program_ids_param
    Array(params.dig(:course, :program_id).presence)
  end
```

- [ ] **Step 8: Update the course form** (`program_id` has no reader anymore — use `select_tag`)

In `app/views/courses/_form.html.haml`, replace the program field (line ~59–62):

```haml
        = f.label :program_id, "Program", class: "form-label"
        = f.select :program_id, options_for_select(Program.includes(:program_group).order(year_started: :desc).map { |p| ["#{p.program_group.code} — #{p.program_code} — #{p.name_en} (#{p.year_started})", p.id] }, course.program_id), { include_blank: "Select a program" }, class: "form-select #{'is-invalid' if course.errors[:program].any?}", data: { controller: "select2" }
        - if course.errors[:program].any?
          .invalid-feedback= course.errors[:program].first
```

with:

```haml
        = f.label :program_id, "Program", class: "form-label"
        = select_tag "course[program_id]", options_for_select(Program.includes(:program_group).order(year_started: :desc).map { |p| ["#{p.program_group.code} — #{p.program_code} — #{p.name_en} (#{p.year_started})", p.id] }, course.programs.first&.id), include_blank: "Select a program", class: "form-select", data: { controller: "select2" }
```

(Single select, optional. `f.label :program_id` still produces `for="course_program_id"`, which matches the `select_tag` id.)

- [ ] **Step 9: Update the course show page**

In `app/views/courses/show.html.haml`, replace the Program block (lines ~31–36):

```haml
            %dt.col-sm-4 Program
            %dd.col-sm-8
              - if @course.program
                = link_to @course.program.name_en, @course.program
              - else
                .text-muted Not assigned
```

with:

```haml
            %dt.col-sm-4 Program
            %dd.col-sm-8
              - if @course.programs.any?
                - @course.programs.each do |program|
                  = link_to program.name_en, program
                  %br
              - else
                .text-muted Not assigned
```

- [ ] **Step 10: Update the course index page**

In `app/views/courses/index.html.haml`, replace the program cell (line ~31):

```haml
              %td= course.program&.short_name.presence || course.program&.name_en
```

with:

```haml
              %td= course.programs.map { |p| p.short_name.presence || p.name_en }.join(", ")
```

- [ ] **Step 11: Drop `program:` from the course fixtures**

In `test/fixtures/courses.yml`, remove the three `program: cp_bachelor` lines (one under each of `intro_computing`, `senior_project`, `gened_course`). The links now come from `test/fixtures/program_courses.yml` (added in Task 1).

- [ ] **Step 12: Fix the now-broken `course_test.rb`**

In `test/models/course_test.rb`:

Remove `program: programs(:cp_bachelor)` from the four `Course.new(...)` calls (the "valid course", "course_no must be unique", "same course_no allowed", and "credits allows nil" tests) — a program is no longer required. For example, the "valid course" test becomes:

```ruby
  test "valid course" do
    course = Course.new(name: "Test Course", course_no: "9999999", revision_year: 2565)
    assert course.valid?
  end
```

Apply the same removal to the other three. Then replace the two association tests (lines ~78–87):

```ruby
  test "belongs to program" do
    course = courses(:intro_computing)
    assert_equal programs(:cp_bachelor), course.program
  end

  test "requires program" do
    course = Course.new(name: "No Program", course_no: "0000006", revision_year: 2565, program_id: nil)
    assert_not course.valid?
    assert_includes course.errors[:program], "must exist"
  end
```

with:

```ruby
  test "has many programs through program_courses" do
    course = courses(:intro_computing)
    assert_includes course.programs, programs(:cp_bachelor)
  end

  test "valid without any program" do
    course = Course.new(name: "No Program", course_no: "0000006", revision_year: 2565)
    assert course.valid?
  end
```

- [ ] **Step 13: Fix the system test's program assertion**

In `test/system/courses_test.rb`, line ~38, replace:

```ruby
    assert_selector "a", text: course.program.name_en
```

with:

```ruby
    assert_selector "a", text: course.programs.first.name_en
```

- [ ] **Step 14: Run the full model/importer suite**

Run: `bin/rails test`
Expected: all pass. (If a test references `course.program`, it was missed — fix it.)

- [ ] **Step 15: Run the system suite**

Run: `bin/rails test:system`
Expected: course show/index/edit/delete and the program-picker render tests pass. This refactor preserves the `_form` program-option text **verbatim** (`"CP — 2101 — Computer Engineering (2540)"`), so the `admin can create a course` select2 pick behaves exactly as before — if it fails on the option text, confirm the same failure exists on the pre-refactor revision (pre-existing, not introduced here) before proceeding.

- [ ] **Step 16: Commit**

```bash
hg add db/migrate/*_backfill_and_drop_course_program_id.rb
hg commit db/migrate app/models/course.rb app/models/program.rb app/models/program_group.rb \
  app/services/importers/course_importer.rb app/controllers/courses_controller.rb \
  app/views/courses/_form.html.haml app/views/courses/show.html.haml app/views/courses/index.html.haml \
  db/schema.rb test/fixtures/courses.yml test/models/course_test.rb test/system/courses_test.rb \
  -m "Make courses↔programs many-to-many: the 1:N belongs_to could not represent a course shared across programs/revisions and blocked ChulaBooster import; backfill links, drop courses.program_id, and move all consumers onto the ProgramCourse join"
```

---

### Task 3: New behavioral tests

Adds coverage for the capabilities the cutover unlocked, at the importer and model level. (Per project convention, tests come after the feature; this is that pass.)

**Files:**
- Create: `test/services/importers/course_importer_test.rb`
- Modify: `test/models/course_test.rb`, `test/models/program_test.rb`, `test/models/program_group_test.rb`

**Interfaces:**
- Consumes: `Importers::CourseImporter#transform_attributes`, `Course#programs`, `Course#import_program`, `Program#courses`, `ProgramGroup#courses`, `ProgramCourse` (Tasks 1–2).

- [ ] **Step 1: Importer program-linking tests** (mirrors the student importer's `transform_attributes` unit-test style — no CSV fixture needed)

Create `test/services/importers/course_importer_test.rb`:

```ruby
require "test_helper"

class Importers::CourseImporterTest < ActiveSupport::TestCase
  test "transform_attributes stashes import_program for a new course" do
    importer = build_course_importer
    attrs = { course_no: "7777777", revision_year: 2565, name: "New One",
              program_name: programs(:cp_bachelor).program_code }
    result = importer.send(:transform_attributes, attrs)
    assert_equal programs(:cp_bachelor), result[:import_program]
  end

  test "transform_attributes links a new program to an existing course" do
    importer = build_course_importer
    course = courses(:intro_computing) # already linked to cp_bachelor via fixtures
    attrs = { course_no: course.course_no, revision_year: course.revision_year,
              name: course.name, program_name: programs(:cp_master).program_code }
    assert_difference "ProgramCourse.count", 1 do
      importer.send(:transform_attributes, attrs)
    end
    assert_includes course.reload.programs, programs(:cp_master)
  end

  test "transform_attributes does not link an unmatched program" do
    importer = build_course_importer
    attrs = { course_no: "7777778", revision_year: 2565, name: "Orphan",
              program_name: "Nonexistent Program" }
    assert_no_difference "ProgramCourse.count" do
      result = importer.send(:transform_attributes, attrs)
      assert_nil result[:import_program]
    end
  end

  private

  def build_course_importer
    di = DataImport.new(target_type: "Course", mode: "upsert", state: "pending", user: users(:admin))
    Importers::CourseImporter.new(di)
  end
end
```

- [ ] **Step 2: Run the importer tests**

Run: `bin/rails test test/services/importers/course_importer_test.rb`
Expected: 3 runs, 0 failures.

- [ ] **Step 3: Model M:N + after_save hook tests**

Append to `test/models/course_test.rb` before the final `end`:

```ruby
  # --- Many-to-many behavior ---

  test "course can belong to multiple programs" do
    course = courses(:intro_computing)
    course.programs << programs(:cp_master)
    assert_equal 2, course.reload.programs.count
    assert_includes course.programs, programs(:cp_bachelor)
    assert_includes course.programs, programs(:cp_master)
  end

  test "import_program links a program after save" do
    course = Course.new(name: "Linked", course_no: "0000007", revision_year: 2565,
                        import_program: programs(:cp_bachelor))
    assert_difference "ProgramCourse.count", 1 do
      course.save!
    end
    assert_includes course.programs, programs(:cp_bachelor)
  end
```

- [ ] **Step 4: Run the course model tests**

Run: `bin/rails test test/models/course_test.rb`
Expected: all pass.

- [ ] **Step 5: Program delete semantics + through**

Append to `test/models/program_test.rb` before the final `end` (uses a throwaway program to avoid the `students`/`staff_programs` restrict-on-delete guards on the fixtures):

```ruby
  test "courses through program_courses" do
    assert_includes programs(:cp_bachelor).courses, courses(:intro_computing)
  end

  test "destroying a program destroys its join rows but keeps the courses" do
    program = Program.create!(program_code: "8888", program_group: program_groups(:cp_group), year_started: 2560)
    program.program_courses.create!(course: courses(:senior_project))
    assert_difference "ProgramCourse.count", -1 do
      assert_no_difference "Course.count" do
        program.destroy!
      end
    end
    assert Course.exists?(courses(:senior_project).id)
  end
```

- [ ] **Step 6: ProgramGroup nested-through guard**

Append to `test/models/program_group_test.rb` before the final `end`:

```ruby
  test "has many courses through programs" do
    group = program_groups(:cp_group)
    assert_includes group.courses, courses(:intro_computing)
  end
```

- [ ] **Step 7: Run the program tests**

Run: `bin/rails test test/models/program_test.rb test/models/program_group_test.rb`
Expected: all pass.

- [ ] **Step 8: Full suite**

Run: `bin/rails test && bin/rails test:system`
Expected: model/importer green; system unchanged from the Task 2 baseline.

- [ ] **Step 9: Commit**

```bash
hg add test/services/importers/course_importer_test.rb
hg commit test/services/importers/course_importer_test.rb test/models/course_test.rb test/models/program_test.rb test/models/program_group_test.rb \
  -m "Cover the new many-to-many behavior: importer links a course into multiple programs, a course belonging to several programs, and program-delete leaving shared courses intact"
```

---

## Notes for the implementer

- **`program_ids=` on a new record:** assigning `@course.program_ids = [id]` before `save` creates the join row on save via autosave — verified pattern for `has_many :through`. On update it replaces the set (fine: the form is the single-program editor for manually-managed courses).
- **Why the importer checks `Course.find_by` first:** `Base#call` only re-saves an upserted record when `changed?` is true, so an unchanged course pointed at a new program would never fire `after_save`. Linking immediately when the course already exists covers that path; the transient `import_program` covers brand-new courses.
- **Don't** reintroduce a program presence validation — the spec deliberately dropped it so Project 2's sync can create a course and link it separately.
