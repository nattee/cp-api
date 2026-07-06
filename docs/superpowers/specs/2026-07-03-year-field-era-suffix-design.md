# Design: Era-explicit year field names (`*_year` → `*_year_be` / `*_year_ce`)

**Date:** 2026-07-03
**Status:** Approved (design), pending implementation plan

## Motivation (the WHY)

The app stores academic years under two different eras — Buddhist Era (B.E.) and
Gregorian/Common Era (C.E.) — but two of the year columns give no hint which era
they hold. This has already burned us once: a live ChulaBooster reconciliation run
matched **0 of ~31,000 grade rows** until someone discovered that `Grade#year` is
C.E. while `Course#revision_year` / `Student#admission_year_be` are B.E. That
lesson is currently preserved only as a comment in
`app/services/chulabooster/mappers/student_courses.rb`.

The convention to fix this already exists in the codebase — `admission_year_be`,
`graduation_year_be`, and `Semester#year_be` all name their era. This change
finishes the job so the era is legible from the column name everywhere: schema,
raw SQL joins, and Ruby.

## Ground truth (verified against `cp_api_development`, 2026-07-03)

| Model.column | rows | stored range | era | marked? |
|---|---|---|---|---|
| `Course.revision_year` | 553 | 543 – 2568 | **B.E.** | no → rename |
| `Program.year_started` | 46 | 0 – 2569 | **B.E.** | no → rename |
| `Grade.year` | 31,079 | 2018 – 2025 | **C.E.** | no → rename |
| `Semester.year_be` | 8 | 2565 – 2568 | B.E. | yes (leave) |
| `Student.admission_year_be` | 7,181 | 2530 – 2568 | B.E. | yes (leave) |
| `Student.graduation_year_be` | 4,483 | 2541 – 2568 | B.E. | yes (leave) |

Data-quality sentinels observed but **out of scope** for this rename (flagged, not
fixed here): `Course.revision_year = 543` (a course stored with revision year "0",
i.e. `0 + 543`); `Program.year_started = 0` (the deliberate `OTHER` placeholder
program). Neither blocks the rename.

## Renames

| From | To | Era |
|---|---|---|
| `courses.revision_year` | `courses.revision_year_be` | B.E. |
| `programs.year_started` | `programs.year_started_be` | B.E. |
| `grades.year` | `grades.year_ce` | C.E. |

`Grade.year` becomes `year_ce`, **not** `year_be` — the data is Gregorian and a
`_be` suffix would encode a falsehood. Marking it `_ce` turns the hidden trap into
a self-documenting name, which is the whole point of the convention.

## Guiding rule for the sweep

**External interface keys stay era-agnostic; internal DB columns + Ruby attributes
carry the era suffix; the `.where(col: external_value)` boundary bridges them.**

This is already the house style — e.g. `student_lookup_tool.rb` exposes an
`admission_year:` JSON key whose value comes from `student.admission_year_be`.
Applying it consistently means:

- **Rename:** DB columns, model attributes/validations/scopes, `accepts_*`/strong
  params attribute lists, importer `attribute:` symbols, view form field
  bindings (`f.number_field :revision_year` → `:revision_year_be`), raw SQL column
  strings (`"grades.year"` → `"grades.year_ce"`), ChulaBooster mapper accessors.
- **Keep stable (external keys):** web URL/query params (`params[:year]`,
  `grades_path(year: …)`), LINE tool JSON argument keys (`arguments["revision_year"]`)
  and result-hash keys. Their *internal* `.where` targets and value expressions
  change; the key strings do not. (User decision: keep params stable — no broken
  bookmarks/frontend.)

## Components

### 1. Migration — `RenameYearFieldsWithEraSuffix`

One reversible migration:

- `rename_column :courses,  :revision_year, :revision_year_be`
- `rename_column :programs, :year_started,  :year_started_be`
- `rename_column :grades,   :year,          :year_ce`
- `rename_index  :courses, "index_courses_on_revision_year_and_course_no",
  "index_courses_on_revision_year_be_and_course_no"` — this index's *name* embeds
  the old column, so rename it for schema honesty.

Grade's unique index `idx_enrollments_unique_student_course_term` has a custom
name that does **not** embed the column; MySQL 8 updates its column reference
automatically on `rename_column`, so no index rename is needed there. Same for
`index_students_on_admission_year_be` (unaffected).

`down` reverses all four operations. In MySQL 8 a column rename is an instant
metadata operation, so 31k grade rows cost nothing.

### 2. Models

- `course.rb` — `validates :revision_year_be`; uniqueness `scope: :revision_year_be`;
  update the "already exists for this revision year" uniqueness scope.
- `program.rb` — `validates :year_started_be`; placeholder `p.year_started_be = 0`.
- `grade.rb` — `validates :year_ce`; uniqueness `scope: [:course_id, :year_ce, :semester]`;
  `scope :for_term, ->(year, semester) { where(year_ce: year, semester:) }` (lambda
  arg name may stay `year`; only the `where` key changes so callers passing
  `params[:year]` are untouched).

### 3. Controllers

`courses`, `grades`, `programs`, `program_groups`, `schedules`, `semesters`,
`students`. Update strong-params attribute lists (`grade_params` → `:year_ce`,
`course_params` → `:revision_year_be`, `program_params` → `:year_started_be`),
raw SQL group strings (`"grades.year"` → `"grades.year_ce"`, `group(:year, …)` →
`group(:year_ce, …)`), and value reads (`@grade.year` → `@grade.year_ce`). **Keep**
`params[:year]`, `params[:start_year]`, `params[:end_year]` and
`grades_path(year: …)` keys as-is.

### 4. Services

- **Importers** (`course`, `grade`, `student`, `schedule`): rename the
  `attribute:` symbols and every downstream reference (`attrs[:revision_year]` →
  `attrs[:revision_year_be]`, `attrs[:year]` → `attrs[:year_ce]`,
  `unique_key_fields`, `transform_attributes`). **Keep** existing `aliases` (they
  match CSV *headers*, unchanged) and **add** the old symbol name as an alias so
  prior exports still auto-map. The `+543 if < 2400` B.E. conversion logic is
  unchanged and stays attached to the B.E. fields; `Grade.year_ce` continues to be
  stored raw (no conversion).
- **Exporters** (`student`, `schedule`): update column reads.
- **ChulaBooster mappers** (`courses`, `programs`, `program_courses`,
  `student_courses`, `students`): `c.revision_year` → `c.revision_year_be`,
  `p.year_started` → `p.year_started_be`, `g.year` → `g.year_ce`. **Rewrite the
  `student_courses.rb` CE-vs-BE comment** to reference `Grade#year_ce` so the
  hard-won explanation still points at the live field name. `Convert.ce_to_be(row["revision_year"])`
  is unchanged — that `"revision_year"` is CB's *source* column, not ours.
- **LINE tools** (`course_lookup`, `course_offering_lookup`, `search`,
  `staff_lookup`, `student_lookup`): update internal column reads
  (`where(revision_year:)` → `where(revision_year_be:)`, `course.revision_year` →
  `course.revision_year_be`, `p.year_started` → `p.year_started_be`). **Keep** the
  LLM-facing JSON argument keys and result keys era-agnostic (already the pattern);
  descriptions already state the era.
- **Reports** (`failing_students`, `group_credit_shortfall`,
  `staff_courses_by_year`, `thesis_credits`) and the `program_charts` concern:
  update column references.
- **Scrapers** (`cas_reg`, `cu_get_reg`): update any `revision_year` /
  semester-year writes to the renamed columns.

### 5. Views (HAML)

Form bindings and display reads across `courses/`, `grades/`, `programs/`,
`program_groups/`, `semesters/`, `students/`, `schedules/`, `course_offerings/`.
Rebind `f.number_field`/`f.label`/`errors[:…]` to the new attribute symbols and
update value interpolations (`g.year` → `g.year_ce`, etc.).

**Era hints on labels (user decision: yes):** where a form/label or detail row
shows one of these fields, add an era hint to the human label — e.g.
`f.label :revision_year_be, "Revision Year (B.E.)"`, `f.label :year_started_be,
"Year Started (B.E.)"`, and `f.label :year_ce, "Year (C.E.)"` on the grade form
(the C.E. hint is the highest-value one). Purely label text; does not change
params or bindings beyond the attribute rename.

### 6. Seeds

`db/seeds/programs.rb` — rename the `year_started:` hash key to `year_started_be:`
(values already `xxxx + 543`, B.E.) and update the header comment.

## Testing

- **Fixtures:** `test/fixtures/courses.yml` (`revision_year` → `revision_year_be`),
  `programs.yml` (`year_started` → `year_started_be`), `grades.yml` (`year` →
  `year_ce`; values already C.E.).
- **Model tests:** `grade_test.rb`, course/program tests — update attribute keys
  and any `errors[:year]` → `errors[:year_ce]` assertions.
- **Controller tests:** `courses_controller_test.rb`, `grades_controller_test.rb`,
  programs — update permitted-params and any assertions on these columns.
- **Service tests:** report tests (`group_credit_shortfall_test`, `thesis_credits_test`,
  `failing_students_test`) that `Grade.create!(… year: …)` → `year_ce:`.
- Run `bin/rails test` and `bin/rails test:system`; the fixtures + validations make
  a stale reference fail loudly. A repo-wide grep for the three old tokens
  (`revision_year`, `year_started`, and grade `year`/`:year`) must come back clean
  except (a) `aliases` arrays deliberately retaining old header names and
  (b) `Convert.ce_to_be(row["revision_year"])` referencing CB's source column.

## Out of scope (explicitly not doing)

- Fixing the `543` course / `0` program sentinel rows (data quality, separate).
- Converting `Grade.year_ce` data to B.E. (rejected — would break CB reconciliation
  again and force lockstep changes across importer/exporter/queries).
- Renaming external URL params or LINE tool JSON keys.
- Changing the grades UI to display B.E. years (pre-existing; not this change).
