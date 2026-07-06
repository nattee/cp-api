# Year Field Era-Suffix Rename — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the three era-ambiguous academic-year columns so the era is legible from the name — `courses.revision_year` → `revision_year_be`, `programs.year_started` → `year_started_be`, `grades.year` → `year_ce` — and update every reference in lockstep.

**Architecture:** One reversible Rails migration renames the columns (and the one index whose name embeds a column). Because ActiveRecord attributes come from the schema, the old names vanish the instant the migration runs, so the whole codebase is red until the sweep completes. There is therefore no per-file green state: each sweep task's deliverable is verified by a **targeted `grep`** (old token gone from that layer), and the single green gate is the full test suite at the end.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, MySQL 8.0, HAML, Minitest + fixtures. VCS is **Mercurial (hg)**, not git.

## Global Constraints

- **VCS is hg, not git.** No `.git` dir exists. Commits only happen if the user opts in; when committing, name explicit files (repos often carry unrelated dirty changes) and lead the message with WHY (per CLAUDE.md). This plan uses **one** commit at the very end because a rename is a single logical change with no committable green intermediate state.
- **The three renames (exact):** `courses.revision_year`→`revision_year_be`; `programs.year_started`→`year_started_be`; `grades.year`→`year_ce`.
- **`Grade` is C.E. → `_ce`, never `_be`.** The data is Gregorian (verified range 2018–2025). A `_be` suffix would encode a falsehood and re-break ChulaBooster reconciliation.
- **External keys stay era-agnostic; internal columns carry the suffix.** Do **not** rename: web URL/query params (`params[:year]`, `params[:start_year]`, `params[:end_year]`, `grades_path(year: …)` keys) or LINE tool JSON argument/result keys (`arguments["revision_year"]`, `admission_year:` output keys). Only their internal `.where(col:)` targets and value expressions (`@grade.year` → `@grade.year_ce`) change.
- **Importer `aliases` need no edits** — the old tokens (`"revision_year"`, `"year"`) are already present in the alias arrays, so old exports keep auto-mapping. Only `attribute:` symbols and internal keys change.
- **Do not touch** the `+543 if < 2400` B.E. conversion logic, the CB-source reference `Convert.ce_to_be(row["revision_year"])` (that `"revision_year"` is ChulaBooster's column), the sentinel rows (`Course.revision_year=543`, `Program.year_started=0`), or the grades UI's display of C.E. years.
- **No new feature tests.** The existing suite + fixtures + validations are the regression guard; we keep them green, we don't add rename-tests.
- **`Semester.year_be`, `Student.admission_year_be`, `Student.graduation_year_be` are already correct — leave them alone.**

---

### Task 1: Migration + schema

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_rename_year_fields_with_era_suffix.rb` (use `bin/rails g migration` so Rails stamps the timestamp)
- Modify (auto): `db/schema.rb`

**Interfaces:**
- Produces: renamed columns `courses.revision_year_be`, `programs.year_started_be`, `grades.year_ce`, and renamed index `index_courses_on_revision_year_be_and_course_no`. Every later task depends on these names existing.

- [ ] **Step 1: Generate the migration file**

Run: `bin/rails g migration RenameYearFieldsWithEraSuffix`
Expected: creates `db/migrate/<timestamp>_rename_year_fields_with_era_suffix.rb`

- [ ] **Step 2: Write the migration body**

Replace the generated file contents with:

```ruby
class RenameYearFieldsWithEraSuffix < ActiveRecord::Migration[8.1]
  def change
    rename_column :courses,  :revision_year, :revision_year_be
    rename_column :programs, :year_started,  :year_started_be
    rename_column :grades,   :year,          :year_ce

    # No explicit rename_index needed: rename_column automatically renames any
    # index whose name follows the index_<table>_on_<column> convention, so the
    # courses unique index becomes index_courses_on_revision_year_be_and_course_no
    # on its own. (grades' index has a custom name and is updated in place.)
    # An explicit rename_index here would raise on a fresh run — the old index
    # name no longer exists by the time it executes.
  end
end
```

**IMPORTANT (corrected during execution):** Do NOT add an explicit `rename_index`.
`rename_column` in Rails auto-renames convention-named indexes in both directions
(verified: forward → `index_courses_on_revision_year_be_and_course_no`, rollback →
back). An explicit `rename_index` raises `Key '…' doesn't exist` on a fresh run
because the index was already renamed by the preceding `rename_column`. All three
operations are reversible inside `change`, so `db:rollback` works with no separate `down`.

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration runs; `db/schema.rb` now shows `revision_year_be`, `year_started_be`, `year_ce`, and the renamed index; the `version:` bumps.

- [ ] **Step 4: Verify the schema changed as intended**

Run:
```bash
bin/rails runner 'puts [
  Course.column_names.include?("revision_year_be"),
  !Course.column_names.include?("revision_year"),
  Program.column_names.include?("year_started_be"),
  Grade.column_names.include?("year_ce"),
  !Grade.column_names.include?("year")
].inspect'
```
Expected: `[true, true, true, true, true]`

Run: `grep -n "revision_year\b\|year_started\b\|\"year\"" db/schema.rb`
Expected: no bare old names remain (only `revision_year_be` / `year_started_be` / `year_ce` and the renamed index).

The app is now red everywhere until Tasks 2–8 finish. That is expected — do **not** run the test suite until Task 9.

---

### Task 2: Models

**Files:**
- Modify: `app/models/course.rb:23-24`
- Modify: `app/models/program.rb:20,27`
- Modify: `app/models/grade.rb:21,26,30`

**Interfaces:**
- Consumes: renamed columns from Task 1.
- Produces: `Grade.for_term(year, semester)` (unchanged signature — the lambda arg stays `year`, only its `where` key becomes `year_ce`); validations on `revision_year_be` / `year_started_be` / `year_ce`.

- [ ] **Step 1: Update `course.rb`**

```ruby
  validates :revision_year_be, presence: true, numericality: { only_integer: true }
  validates :course_no, uniqueness: { scope: :revision_year_be, message: "already exists for this revision year" }
```

- [ ] **Step 2: Update `program.rb`**

Line 20:
```ruby
  validates :year_started_be, presence: true, numericality: { only_integer: true }
```
Line 27 (inside `self.placeholder`):
```ruby
      p.year_started_be = 0
```

- [ ] **Step 3: Update `grade.rb`**

Line 21:
```ruby
  validates :year_ce, presence: true, numericality: { only_integer: true }
```
Lines 26-27:
```ruby
  validates :student_id, uniqueness: { scope: [:course_id, :year_ce, :semester],
                                       message: "is already enrolled in this course for this term" }
```
Line 30 (arg name stays `year`; only the `where` key changes so `params[:year]` callers are untouched):
```ruby
  scope :for_term, ->(year, semester) { where(year_ce: year, semester: semester) }
```

- [ ] **Step 4: Verify models load and the layer is grep-clean**

Run: `bin/rails runner 'Course; Program; Grade; puts "loaded"'`
Expected: `loaded` (no `ActiveModel::UnknownAttributeError` / NameError).

Run: `grep -rn "revision_year\b\|year_started\b\|:year\b\|\byear:" app/models/`
Expected: only `revision_year_be` / `year_started_be` / `year_ce` (no bare old tokens).

---

### Task 3: Importers

**Files:**
- Modify: `app/services/importers/course_importer.rb` (grep the whole file for `revision_year`)
- Modify: `app/services/importers/grade_importer.rb` (attr `:year`, `find_existing_record`, `unique_key_fields`, `transform_attributes`, and the `revision_year:` **column keys** inside `resolve_course` / `resolve_course_by_no`)
- Modify: `app/services/importers/schedule_importer.rb` (`find_course`'s `Course.find_by(..., revision_year:)`, plus its `attribute: :revision_year` def + `attrs[:revision_year]` call site)
- Modify: `app/services/importers/student_importer.rb` (**added during execution** — raw-SQL `where("year_started <= ?", …)` / `order(year_started: :desc)` in program resolution, and the `fixed_options` display, all → `year_started_be`; `admission_year_be` stays)

**Interfaces:**
- Consumes: renamed columns (Task 1), model validations (Task 2).
- Produces: importers that build `Course`/`Grade` records with the new attribute names.

**Transformation rule:** in these files, every place a symbol/hash-key names one of the three columns (whether as an importer `attribute:`, an `attrs[:…]` key, an `.find_by`/`.new`/`.create!`/assignment column key, or a `unique_key_fields` entry) gets the era suffix. Local variable / method-parameter names may stay as-is (`revision_year`, `year` as *values* are fine). **Do not** touch `aliases`, `help` prose, or the `+543` lines.

- [ ] **Step 1: `course_importer.rb`**

- `attribute: :revision_year` → `attribute: :revision_year_be` (label `"Revision Year (B.E.)"` already correct — keep).
- `find_existing_record`: `Course.find_by(course_no: attrs[:course_no], revision_year: attrs[:revision_year])` → `..., revision_year_be: attrs[:revision_year_be])`.
- `unique_key_fields`: `[ :course_no, :revision_year ]` → `[ :course_no, :revision_year_be ]`.
- `transform_attributes`: the coerce list `[:revision_year, …]` → `[:revision_year_be, …]`; the block `if attrs[:revision_year]` / `attrs[:revision_year] += 543 …` → `attrs[:revision_year_be]` (keep the `+= 543`); the later `Course.find_by(course_no: attrs[:course_no], revision_year: attrs[:revision_year])` in the program-linking branch → `revision_year_be: attrs[:revision_year_be]`.
- Leave `Program.…order(year_started: :desc)` / `(#{p.year_started})` **for now** — those are `year_started`, handled here too: change `year_started` → `year_started_be` in the `fixed_options` lambda and the name-lookup `.order(year_started: :desc)` calls.

- [ ] **Step 2: `grade_importer.rb`**

- `attribute: :year` → `attribute: :year_ce` (keep its `aliases: %w[academic_year year ปีการศึกษา]`).
- `find_existing_record`: `year: attrs[:year]` → `year_ce: attrs[:year_ce]`.
- `unique_key_fields`: `[:student_id, :course_id, :year, :semester]` → `[…, :year_ce, :semester]`.
- `transform_attributes` coerce line: `attrs[:year] = attrs[:year].to_i if attrs[:year]` → `attrs[:year_ce] = attrs[:year_ce].to_i if attrs[:year_ce]`.
- In `resolve_course` / `resolve_course_by_no`: the **column keys** `Course.find_by(course_no:, revision_year:)`, `copy.revision_year = revision_year`, `Course.create!(… revision_year: revision_year …)`, and `ABS(revision_year - …)` in the raw SQL order string all become `revision_year_be`. The method **parameter/local** named `revision_year` may stay (it holds a B.E. value).

- [ ] **Step 3: `schedule_importer.rb`**

In `find_course`, change the `revision_year:` column key in `Course.find_by(...)` (and any `ABS(revision_year …)` raw SQL) to `revision_year_be`. **Keep** the `year += 543` line at ~260 — that writes `Semester.year_be`, which is unchanged.

- [ ] **Step 4: Verify the layer is grep-clean**

Run:
```bash
grep -rn "revision_year\b\|year_started\b\|:year\b\|\byear:\|attrs\[:year\]" app/services/importers/ \
  | grep -v "revision_year_be\|year_started_be\|year_ce\|aliases\|academic_year\|# \|help:\|\"year\""
```
Expected: no lines (every hit is a renamed token, an alias, prose, or the `year_be`/`year += 543` semester path). Manually confirm any remaining `year_be` hits are the semester conversion, not our fields.

---

### Task 4: ChulaBooster mappers + comment rewrite

**Files:**
- Modify: `app/services/chulabooster/mappers/courses.rb`, `programs.rb`, `program_courses.rb`, `students.rb`, `student_courses.rb`

**Interfaces:**
- Consumes: renamed model accessors (Task 2).
- Produces: reconciliation mappers that read the new accessor names.

**Rule:** change only our **local** accessors — `c.revision_year` → `c.revision_year_be`, `p.year_started` → `p.year_started_be`, `g.year` → `g.year_ce`, and any `:year_started`/`:revision_year` symbol in a comparison tuple. **Do not** change `Convert.ce_to_be(row["revision_year"])` or any `row["…"]` — those are ChulaBooster's source columns.

- [ ] **Step 1: Edit the mappers**

- `courses.rb`: `cb_key` uses `Convert.ce_to_be(row["revision_year"])` — that is CB's source, **leave it**. Change any `c.revision_year` local accessor if present.
- `programs.rb`: comparison tuple `[:year_started, p.year_started, Convert.ce_to_be(row["revision_year"]), true]` → `[:year_started_be, p.year_started_be, Convert.ce_to_be(row["revision_year"]), true]` (the `row["revision_year"]` stays — CB source).
- `students.rb`: `[:admission_year_be, s.admission_year_be, …]` is already correct — leave.
- `student_courses.rb`: in `local_key`, `g.year` → `g.year_ce` and `g.course.revision_year` → `g.course.revision_year_be`.

- [ ] **Step 2: Rewrite the hard-won CE-vs-BE comment in `student_courses.rb`**

Update the NOTE block (currently referencing `Grade#year`) so it names the live field:

```ruby
      # NOTE (fixed after a live run against real ChulaBooster data returned matched: 0 across all
      # 31,079 local / 49,502 CB rows): Grade#year_ce is Gregorian/CE (confirmed real range 2018..2025),
      # NOT Buddhist Era like course.revision_year_be / admission_year_be — hence the column is named
      # _ce, and CB's already-CE academic_year must NOT be converted to BE here. And CB's semester_code
      # is a string like "s1"/"s2"/"s3", not a plain integer like local's Grade#semester —
      # Convert.semester_number strips the "s" prefix.
```

- [ ] **Step 3: Verify grep-clean**

Run:
```bash
grep -rn "\.revision_year\b\|\.year_started\b\|g\.year\b\|:year_started\b\|:revision_year\b" app/services/chulabooster/
```
Expected: no bare old accessors (renamed ones and `row["revision_year"]` / `Convert.ce_to_be(row["revision_year"])` are fine and won't match `\.revision_year`).

---

### Task 5: LINE tools (external-key discipline)

**Files:**
- Modify: `app/services/line/tools/course_lookup_tool.rb`, `course_offering_lookup_tool.rb`, `search_tool.rb`, `staff_lookup_tool.rb`, `student_lookup_tool.rb`

**Interfaces:**
- Consumes: renamed columns/accessors.
- Produces: unchanged LLM-facing tool schemas; only internal DB reads change.

**Rule:** change internal DB column reads and value expressions to the new names; **keep every JSON key the LLM sees** (schema `properties` keys, `arguments["…"]` reads, and result-hash keys) exactly as-is.

- [ ] **Step 1: `course_lookup_tool.rb`**

- Keep the schema property `revision_year:` and `arguments["revision_year"]` and the local `revision_year = arguments["revision_year"]` **as-is** (external contract; description already says "Buddhist Era").
- Change the internal query key `scope.where(revision_year: revision_year)` → `scope.where(revision_year_be: revision_year)` and `scope.order(course_no: :asc, revision_year: :desc)` → `revision_year_be: :desc`.
- Change result value `revision_year: course.revision_year` → `revision_year: course.revision_year_be` (key stays `revision_year:`, value gets `_be`).
- Change `(#{prog.year_started})` → `(#{prog.year_started_be})`.
- The `describe_filters` string `"revision_year=#{revision_year}"` reads the local value — leave the label text as-is.

- [ ] **Step 2: `course_offering_lookup_tool.rb`**

- Result value `revision_year: course.revision_year` → `revision_year: course.revision_year_be` (key stays).
- `o.semester.year_be` — unchanged (semester is already `_be`).

- [ ] **Step 3: `search_tool.rb`**

- `scope.order(revision_year: :desc)` → `revision_year_be: :desc`.
- Result value `revision_year: c.revision_year` → `revision_year: c.revision_year_be`.
- `(#{s.program.year_started})` → `(#{s.program.year_started_be})`.

- [ ] **Step 4: `staff_lookup_tool.rb`**

- `(#{p.program_group.code} (#{p.year_started}))` → `#{p.year_started_be}`.

- [ ] **Step 5: `student_lookup_tool.rb`**

- `student.program.year_started` → `year_started_be`.
- `admission_year_be` reads and the `admission_year:` output key are already correct — leave.

- [ ] **Step 6: Verify grep-clean**

Run:
```bash
grep -rn "\.revision_year\b\|\.year_started\b\|where(revision_year:\|order(revision_year:" app/services/line/tools/
```
Expected: no bare old accessors/keys. Sanity-check that schema `properties`/`arguments` keys still read `revision_year` (intentional external contract).

---

### Task 6: Remaining Ruby (controllers, reports, exporters, scrapers, concern)

**Files:**
- Modify: `app/controllers/courses_controller.rb`, `grades_controller.rb`, `programs_controller.rb`, `program_groups_controller.rb`, `schedules_controller.rb`, `semesters_controller.rb`, `students_controller.rb`
- Modify: `app/controllers/concerns/program_charts.rb`
- Modify: `app/services/reports/failing_students.rb`, `group_credit_shortfall.rb`, `staff_courses_by_year.rb`, `thesis_credits.rb`
- Modify: `app/services/exporters/student_exporter.rb`, `schedule_exporter.rb`
- Modify: `app/services/scrapers/cas_reg.rb`, `cu_get_reg.rb`

**Interfaces:**
- Consumes: renamed columns, `Grade.for_term` (unchanged signature).

**Rule:** internal column references get the suffix; **URL/query param keys stay stable**. Concretely in `grades_controller.rb` / `courses_controller.rb`: keep `params[:year]`, `params[:start_year]`, `params[:end_year]`, and the `grades_path(year: …)` **key**; change the value read (`@grade.year` → `@grade.year_ce`), strong-params attribute lists (`:year` → `:year_ce`, `:revision_year` → `:revision_year_be`, `:year_started` → `:year_started_be`), raw SQL strings (`"grades.year"` → `"grades.year_ce"`), and `group(:year, …)` → `group(:year_ce, …)`.

- [ ] **Step 1: Controllers + concern**

Grep each file and apply the rule. Key spots (verify by grep, not memory):
- `grades_controller.rb`: `.for_term(params[:year], params[:semester])` — **unchanged** (external param + unchanged scope); `redirect_to grades_path(year: @grade.year, …)` → value `@grade.year_ce`, key `year:` stays; `group("courses.course_no", "grades.year", "grades.semester", "grades.grade")` → `"grades.year_ce"`; `grade_params` permit list `:year` → `:year_ce`.
- `courses_controller.rb`: `params[:year]`/`@selected_year` — **unchanged** (external); `.group(:year, :semester, :grade)` (grouping grades) → `:year_ce`; `course_params` `:revision_year` → `:revision_year_be`.
- `programs_controller.rb`: `program_params` `:year_started` → `:year_started_be`; any `.order(year_started:)` → `year_started_be`.
- `program_groups_controller.rb`, `schedules_controller.rb`, `semesters_controller.rb`, `students_controller.rb`, `program_charts.rb`: grep for the three old tokens and swap internal column refs; keep `params[:start_year]`/`params[:end_year]`.

- [ ] **Step 2: Reports, exporters, scrapers**

- `failing_students.rb`: `.where(courses: {…}, grade: "F", year: year)` → `year_ce: year`; `"#{g.year}/#{g.semester}"` → `g.year_ce`.
- `group_credit_shortfall.rb`, `thesis_credits.rb`, `staff_courses_by_year.rb`: grep + swap column refs (`admission_year_be` stays).
- `student_exporter.rb`: `admission_year_be`/`graduation_year_be` reads are already correct — swap only `revision_year`/`year_started`/grade `year` if present.
- `schedule_exporter.rb`: `semester.year_be` unchanged; swap `revision_year` if present.
- `cas_reg.rb`, `cu_get_reg.rb`: swap `revision_year` writes → `revision_year_be`; `year += 543` semester paths (writing `year_be`) unchanged.

- [ ] **Step 3: Verify grep-clean**

Run:
```bash
grep -rn "revision_year\b\|year_started\b" app/controllers/ app/services/reports/ app/services/exporters/ app/services/scrapers/ | grep -v "_be\b"
grep -rn "\.year\b\|:year\b\|\"grades.year\"\|group(:year\b\|year: @\|year: g\." app/controllers/ app/services/reports/ | grep -v "year_ce\|year_be\|_year\|params\[:year\]\|academic_year\|start_year\|end_year"
```
Expected: remaining hits are only intentional external params (`params[:year]`, `for_term(params[:year]…)`) — confirm each by eye.

---

### Task 7: Views (HAML) + era-hint labels + seeds

**Files:**
- Modify (grep to find exact lines): `app/views/courses/_form.html.haml`, `index.html.haml`, `show.html.haml`; `app/views/grades/_form.html.haml`, `index.html.haml`, `show.html.haml`; `app/views/programs/_form.html.haml`, `index.html.haml`, `show.html.haml`; `app/views/program_groups/show.html.haml`; `app/views/semesters/_form.html.haml`, `index.html.haml`; `app/views/students/_form.html.haml`, `show.html.haml`; `app/views/schedules/workload.html.haml`; `app/views/course_offerings/_form.html.haml`
- Modify: `db/seeds/programs.rb`

**Interfaces:**
- Consumes: renamed columns; form bindings must match the new attribute symbols or the form errors out.

- [ ] **Step 1: Rebind form fields and value reads**

For each view, grep for the three old tokens and swap:
- `f.number_field :revision_year` → `:revision_year_be`; `f.label :revision_year` and `grade.errors[:revision_year]` → `:revision_year_be`.
- `f.number_field :year_started` → `:year_started_be` (+ its `f.label` / `errors[:year_started]`).
- `f.number_field :year` (grade form) → `:year_ce`; `f.label :year` + `grade.errors[:year]` (all three refs on lines 34/38/39/40) → `:year_ce`.
- Value interpolations: `@grade.year` → `@grade.year_ce`, `g.year` → `g.year_ce`, `#{g.year}/#{g.semester}` → `#{g.year_ce}/#{g.semester}`, `sort_by { |g| [… g.year, …] }` / `[-g.year, -g.semester]` → `g.year_ce`.
- **Keep** `select_tag :year, options_for_select(@available_years, params[:year])` and the `params[:year]` guards in `grades/index.html.haml` — external filter key stays.

- [ ] **Step 2: Add era hints to the human labels (user decision: yes)**

Give the visible label text an explicit era. Where a form uses the default label, pass an explicit string:
```haml
= f.label :revision_year_be, "Revision Year (B.E.)", class: "form-label"
= f.label :year_started_be, "Year Started (B.E.)", class: "form-label"
= f.label :year_ce, "Year (C.E.)", class: "form-label"
```
The grade form's `Year (C.E.)` hint is the highest-value one (it's the odd C.E. field). Apply the same hint to any show-page `<dt>`/label that displays these fields (e.g. `grades/show.html.haml` term row, `courses/show.html.haml` revision year).

- [ ] **Step 3: Seeds**

`db/seeds/programs.rb`: rename every `year_started:` hash key to `year_started_be:` (values already `xxxx + 543`, B.E.). Update the header comment `# year_started values are in Buddhist Era (B.E.)` → `# year_started_be values are in Buddhist Era (B.E.)`.

- [ ] **Step 4: Verify grep-clean**

Run:
```bash
grep -rn "revision_year\b\|year_started\b" app/views/ db/seeds/ | grep -v "_be\b"
grep -rn ":year\b\|\.year\b\|g\.year\b\|@grade\.year\b" app/views/ | grep -v "year_ce\|year_be\|_year\|params\[:year\]\|:year,\s*options_for_select\|available_years"
```
Expected: remaining `:year, options_for_select`/`params[:year]` hits are the intentional external filter key; everything else is renamed.

---

### Task 8: Fixtures + tests

**Files:**
**Grep-authoritative over all of `test/`.** The list below is the known set;
`grep -rnE "revision_year\b|year_started\b" test/` and the grade-`year` grep are the
real checklist — fix EVERY occurrence.
- Modify: `test/fixtures/courses.yml` (3 rows), `test/fixtures/programs.yml` (2 rows), `test/fixtures/grades.yml` (4 rows)
- Modify: `test/models/grade_test.rb`, and any course/program model test referencing the old columns
- Modify: `test/controllers/courses_controller_test.rb`, `grades_controller_test.rb`, and programs controller test
- Modify: `test/services/reports/group_credit_shortfall_test.rb`, `thesis_credits_test.rb`, `failing_students_test.rb`
- Modify (**added during execution — were missing from this list**): `test/services/chulabooster/composite_mappers_test.rb`, `mappers_test.rb`, `reconciler_test.rb`; `test/services/exporters/schedule_exporter_test.rb`; `test/services/line/tools/course_lookup_tool_test.rb`, `search_tool_test.rb`; `test/system/courses_test.rb`, `data_imports_test.rb`

**Interfaces:**
- Consumes: renamed columns. Fixtures must use the new keys or fixture loading raises `Fixture … has no column`.

- [ ] **Step 1: Fixtures**

- `courses.yml`: `revision_year: 2565`/`2565`/`2560` → `revision_year_be:` (same values).
- `programs.yml`: `year_started: 2540`/`2545` → `year_started_be:` (same values).
- `grades.yml`: `year: 2024`/`2024`/`2024`/`2022` → `year_ce:` (same values — already C.E.).

- [ ] **Step 2: Tests**

Swap attribute keys in every test that sets or asserts these columns:
- `grade_test.rb`: `year: 2025` → `year_ce: 2025` (both occurrences, lines ~8 and ~102); `grade.year = nil` → `grade.year_ce = nil`; `assert_includes grade.errors[:year], …` → `grade.errors[:year_ce]`.
- Report tests: `Grade.create!(… year: 2023 …)` / `year: 2022` → `year_ce:`.
- Course/program/controller tests: `revision_year:` → `revision_year_be:`, `year_started:` → `year_started_be:`, and any permitted-params or assertion on these columns.

- [ ] **Step 3: Verify grep-clean across test/**

Run:
```bash
grep -rn "revision_year\b\|year_started\b" test/ | grep -v "_be\b"
grep -rn "year:\|:year\b\|\.year\b\|errors\[:year\]" test/ | grep -v "year_ce\|year_be\|_year\|academic_year"
```
Expected: no bare old tokens in `test/`.

---

### Task 9: Final verification (green gate) + optional commit

**Files:** none (verification only).

- [ ] **Step 1: Global grep for stragglers**

Run:
```bash
grep -rn "revision_year\b" app/ db/ lib/ test/ config/ | grep -v "revision_year_be\|Convert.ce_to_be(row\[.revision_year.\])\|aliases\|revision year"
grep -rn "year_started\b" app/ db/ lib/ test/ config/ | grep -v "year_started_be"
```
Expected: the only `revision_year` hits are (a) `Convert.ce_to_be(row["revision_year"])` (CB source column) and (b) `aliases`/`help`/description prose retaining the old header word. Zero `year_started` (bare). Investigate anything else.

- [ ] **Step 2: Run the full unit/model suite**

Run: `bin/rails test`
Expected: all green. A stale reference surfaces here as a `NoMethodError`/`UnknownAttributeError` or a fixture-load failure — fix it and re-run.

- [ ] **Step 3: Run the system suite**

Run: `bin/rails test:system`
Expected: all green (forms still submit; era-hint labels render).

- [ ] **Step 4: Smoke-check the app boots and reads real data**

Run:
```bash
bin/rails runner 'puts Course.minimum(:revision_year_be); puts Program.maximum(:year_started_be); puts Grade.minimum(:year_ce)'
```
Expected: values in the ranges from the spec (`543`/`2569`/`2018`) — proves the data survived the rename and the new accessors read it.

- [ ] **Step 5: Commit — only if the user opts in**

This is one logical change → one commit. hg, explicit files, WHY-first message:
```bash
hg add db/migrate/<timestamp>_rename_year_fields_with_era_suffix.rb
hg commit db/migrate/<timestamp>_rename_year_fields_with_era_suffix.rb db/schema.rb \
  app/models/course.rb app/models/program.rb app/models/grade.rb \
  app/services/importers/course_importer.rb app/services/importers/grade_importer.rb app/services/importers/schedule_importer.rb \
  app/services/chulabooster/mappers/programs.rb app/services/chulabooster/mappers/student_courses.rb \
  app/services/line/tools/course_lookup_tool.rb app/services/line/tools/course_offering_lookup_tool.rb app/services/line/tools/search_tool.rb app/services/line/tools/staff_lookup_tool.rb app/services/line/tools/student_lookup_tool.rb \
  app/controllers/ app/services/reports/ app/services/exporters/ app/services/scrapers/ app/controllers/concerns/program_charts.rb \
  app/views/ db/seeds/programs.rb test/ \
  -m "Name the era in academic-year columns so it can't be misread

The reconciliation of grades against ChulaBooster once matched 0 of ~31k
rows because Grade#year is Gregorian while revision_year/admission_year are
Buddhist Era — an ambiguity invisible in the column names. This makes the
era part of the name everywhere.

- rename courses.revision_year -> revision_year_be (B.E.)
- rename programs.year_started -> year_started_be (B.E.)
- rename grades.year -> year_ce (Gregorian/C.E., NOT B.E.)
- add (B.E.)/(C.E.) hints to the corresponding form labels
- external URL/query params and LINE tool JSON keys kept stable"
```
(Adjust the explicit file list to exactly what changed; do not `hg commit` bare — name files, since the repo may carry unrelated dirty changes.)

---

## Notes for the executor

- **Order matters only for Task 1** (migration first). Tasks 2–8 can proceed in any order but the suite stays red until all are done — that is expected; the green gate is Task 9.
- **The three grep exceptions** you will keep seeing and must NOT "fix": importer `aliases` (`"revision_year"`, `"year"`), `Convert.ce_to_be(row["revision_year"])` (CB source), and `help:`/description prose using the words "revision year".
- If `bin/rails test` complains about a pending migration in the test DB, run `bin/rails db:test:prepare` first (it loads `schema.rb` into `cp_api_test`).
