# Course ↔ Program Many-to-Many Re-model

**Date:** 2026-06-30
**Status:** Approved design — pending implementation plan
**Project:** 1 of 2. This branch is a prerequisite for **Project 2: ChulaBooster data sync** (separate spec, later).

---

## Why (motivation)

CP-API currently models `Course belongs_to :program`. In the schema, each `(course_no, revision_year)`
is a **single row tied to exactly one program**:

```ruby
# db/schema.rb — courses
t.bigint "program_id", null: false
t.index ["revision_year", "course_no"], unique: true
add_foreign_key "courses", "programs"
```

This is wrong for the domain:

- A course can belong to **several programs at once** (e.g. a foundational course shared by the CP and
  CEDT curricula in the same revision year).
- Curricula differ by revision: CP-2566 and CP-2561 include *different* discrete-math courses. "A course
  belongs to a program" conflates the course with its curriculum placement.
- The unique `(revision_year, course_no)` index makes a shared course **physically unrepresentable** — you
  cannot have the same `(course_no, revision_year)` in two programs.

It also **blocks Project 2.** ChulaBooster's `courses` export carries **no program field at all** — program
membership lives only in its `program_courses` table, which is a true many-to-many join. Under the current
`program_id NOT NULL` model a ChulaBooster course **cannot be imported faithfully**: you would be forced to
invent a single program for something that is program-agnostic.

**Decision:** re-shape `Course ↔ Program` from 1:N to a proper many-to-many through a join model
(`ProgramCourse`). Do it as a **pure, non-regressive refactor** on its own branch first, so Project 2's sync
is built once against the correct schema.

---

## Scope

**In scope**
- New `ProgramCourse` join model + `program_courses` table.
- Backfill the existing 1:1 links into the join; drop `courses.program_id`.
- Update associations (`Course`, `Program`, `ProgramGroup`), the course importer, controller, and views to
  the M:N shape.
- Preserve current UX: a **single-program selector** on the course form (now optional).

**Out of scope** (deferred / other project)
- ChulaBooster sync itself — **Project 2**.
- Populating `course_group_code` / `course_type` — Project 2 (columns are added now but left null).
- Multi-program selection UI, or any curriculum-management page.
- Any change to `Student ↔ Program` or `Staff ↔ Program` — those are correctly 1:N and untouched.

---

## Decisions captured

| Decision | Choice | Rationale |
|---|---|---|
| Implementation approach | **A — `has_many :through` join model, big-bang migration** | Clean end state; blast radius small (~6–8 spots); join *model* needed to carry Project-2 attributes. (Rejected: expand/contract — over-engineered at this scale; HABTM — can't carry join attributes.) |
| Branch scope | **Pure non-regressive refactor** | No UI feature work; keep the single-program form selector. |
| `remark` on join | **Add it** | Local annotation; the sync never overwrites it (managed-vs-local policy). |
| "Course must have a program" | **No invariant** | Courses may have 0/1/many programs; also eases Project 2 (create course, link separately). |
| `course_group_code` + `course_type` | **Add now, nullable/inert** | One migration instead of two; certain Project-2 need. |
| Sequencing | **Re-model first, then sync** | Course sync is incompatible with the old 1:N model; build sync once, correctly. |

---

## Data model

**New table `program_courses`:**

```ruby
create_table :program_courses do |t|
  t.references :program, null: false, foreign_key: true
  t.references :course,  null: false, foreign_key: true
  t.string  :course_group_code   # nullable — Project 2 (ChulaBooster) owns
  t.integer :course_type         # nullable — Project 2 (ChulaBooster) owns
  t.string  :remark              # nullable — local annotation, sync never overwrites
  t.timestamps
end
add_index :program_courses, [:program_id, :course_id], unique: true
```

**New model:**

```ruby
class ProgramCourse < ApplicationRecord
  belongs_to :program
  belongs_to :course
  validates :course_id, uniqueness: { scope: :program_id }
end
```

**Association changes:**

```ruby
# app/models/course.rb — REMOVE `belongs_to :program`; ADD:
has_many :program_courses, dependent: :destroy
has_many :programs, through: :program_courses
# (no presence validation on programs)

# app/models/program.rb — was `has_many :courses, dependent: :restrict_with_error`:
has_many :program_courses, dependent: :destroy
has_many :courses, through: :program_courses

# app/models/program_group.rb — was `has_many :courses, through: :programs`:
has_many :program_courses, through: :programs
has_many :courses, -> { distinct }, through: :program_courses
```

**Semantic shift on delete:** destroying a `Program` now destroys its **join rows**, not its courses (a
course may live in other programs). This replaces the old `restrict_with_error` guard and is correct M:N
behavior.

---

## Migration & backfill

Two migrations — schema-create kept separate from the cutover.

**Migration 1 — `CreateProgramCourses`:** the join table + unique index above.

**Migration 2 — `BackfillAndDropCourseProgramId`:**

```ruby
def up
  execute <<~SQL
    INSERT INTO program_courses (program_id, course_id, created_at, updated_at)
    SELECT program_id, id, NOW(), NOW() FROM courses
  SQL

  # backfill safety check — the automatic "recheck"
  pc = select_value("SELECT COUNT(*) FROM program_courses").to_i
  c  = select_value("SELECT COUNT(*) FROM courses").to_i
  raise "backfill count mismatch (#{pc} != #{c}) — aborting" unless pc == c

  remove_foreign_key :courses, :programs   # MUST precede the column drop (MySQL)
  remove_column :courses, :program_id      # also drops index_courses_on_program_id
end

def down
  add_column :courses, :program_id, :bigint
  execute <<~SQL
    UPDATE courses c
    JOIN program_courses pc ON pc.course_id = c.id
    SET c.program_id = pc.program_id          -- arbitrary program if >1 (lossy)
  SQL
  change_column_null :courses, :program_id, false
  add_index :courses, :program_id, name: "index_courses_on_program_id"
  add_foreign_key :courses, :programs
  execute "DELETE FROM program_courses"
end
```

- Backfill is a faithful 1:1 copy (every existing course has exactly one program today): **553 rows**.
- `down` is cleanly reversible **immediately after this branch** (each course still has one program). It
  becomes lossy only once Project 2 introduces multi-program courses — the expected one-way door.
- Safety nets: the count assertion above, the `down` migration, and the DB backup. **Backups protect data;
  tests protect behavior** — both are used.

---

## Code & view changes

| File | Now | Change |
|---|---|---|
| `models/course.rb` | `belongs_to :program` | `has_many :program_courses` + `:programs, through:` |
| `models/program.rb` | `has_many :courses, restrict_with_error` | through `:program_courses`, `dependent: :destroy` |
| `models/program_group.rb` | `has_many :courses, through: :programs` | nested through `:program_courses` (`distinct`) |
| `services/importers/course_importer.rb` (~L117) | `attrs[:program_id] = program&.id` | after the course is saved, `ProgramCourse.find_or_create_by!(course:, program:)` — **the only real logic change**; `find_or_create_by!` + unique index keep `upsert`/`create_only` from duplicating links |
| `controllers/courses_controller.rb` (~L92) | permits `:program_id` | permit single `program_id`; set `@course.program_ids = Array(program_id.presence)` (blank → no link; keeps single-select UX, now optional) |
| `views/courses/_form.html.haml` (~L59) | single `program_id` select | same dropdown; selected = `@course.programs.first&.id`; optional |
| `views/courses/show.html.haml` (~L33) | `@course.program.name_en` | iterate `@course.programs` (0–1 today), link each; render "—" if empty |
| `views/courses/index.html.haml` (~L31) | `course.program&.short_name` | `course.programs.map { … }.join(", ")`; add `.includes(:programs)` to the index query (avoid N+1) |
| `db/seeds/*` | — | audit for any seed building courses with `program:`; verify during implementation |

Everything except the importer is a mechanical association/display swap. The importer carries the only
behavioral risk and is covered by tests below.

---

## Testing

Non-regressive refactor → goal is **every existing behavior preserved, plus the new M:N capability proven.**
Written after the refactor lands (confirm before writing, per `CLAUDE.md`).

**Fixtures**
- `test/fixtures/courses.yml` — remove the `program:` line from each course.
- New `test/fixtures/program_courses.yml` — one join row per existing course fixture, recreating today's 1:1
  so existing tests that expect a course→program still pass via `course.programs`.

**Model tests**
- New `program_course_test.rb` — both `belongs_to`; uniqueness of `course_id` scoped to `program_id`;
  fixtures valid.
- `course_test.rb` — update the `course.program` assertion to `assert_includes course.programs, …`; add: a
  course with **zero** programs is valid; a course can have **multiple** programs.
- `program_test.rb` — `program.courses` (through) works; **destroying a program destroys join rows but leaves
  the courses**.
- `program_group_test.rb` — `program_group.courses` (nested through, `distinct`) still returns courses.

**Importer tests** (`course_importer`)
- Import with a program column creates the `Course` **and** one `ProgramCourse`.
- Re-import (upsert) of the same course+program **does not duplicate** the link.
- Same `(course_no, revision_year)` under a **different** program **adds a second link** (the new M:N
  capability).

**System tests** (`courses_test.rb`)
- Update the `course.program.name_en` assertion to `course.programs.first.name_en`.
- Course form picks a program (single select) → save creates the link; show lists program(s); index lists
  program(s); a program-less course renders "—".

Run: `bin/rails test` (model/importer) and `bin/rails test:system`.

---

## Appendix — Project 2 readiness (ChulaBooster API findings)

Recorded from live probing of the ChulaBooster External API (`/api/ext/`; creds in Rails credentials under
`:chulabooster`). **Context only — not in scope for this branch.**

- **Capabilities:** the key (bound to personal account `net.nattee`) now holds all `export:*` (students,
  courses, programs, student_courses, program_courses) plus `read:*`. *Recommendation:* provision a dedicated
  **department-scoped service account** for the production sync rather than binding to a personal identity.
- **Crosswalks confirmed against live data:**
  - CB `program_id` ↔ CP `program_code` (CB `program_code` 6-digit ↔ CP **`alternative_program_code`** — an
    existing slot).
  - `*_alt` fields = **Thai**; base field = **English**.
  - CB `course_id` = `revision_year` + `course_no`; resolve courses by `(course_no, revision_year)`.
  - Years are **CE** — apply the existing CE→BE (`+543`) convention.
  - `Grade.source` is a ready-made provenance slot ("chulabooster").
- **`ProgramCourse` ↔ CB `program_courses`:** exact structural match (`program_id`, `course_id`/`course_no`,
  `course_group_code`, `course_type`).
- **Historical depth:** programs back to 1976, courses to 1996, students to ≥1993; `changed_since` with an
  epoch date returns full history (initial backfill works).
- **⚠️ Performance:** `student_courses` export is ≈ **26s fixed per request, independent of page size**
  (26.5s for `limit=2`; 26.1s for `limit=100`). Project 2 **must** page it at `limit=500` and run a
  **resumable, checkpointed background job** — small pages would take days.
- **Pagination/delta:** keyset via opaque `next_cursor` (base64 of `update_time|pk`); `changed_since` for
  deltas; `limit ≤ 500` for export, search capped at 200.

## Project 2 — Phase 1: Reconciliation (dry-run diff) — REQUIRED before any write

Because Project 2 is an **authoritative** sync (CB overwrites managed fields), its first phase is a
**read-only reconciliation report** that runs *after* this re-model and *before* any write. It diffs each CB
export against the data already in the local DB (from earlier CSV imports), keyed by business key, and
buckets every record as **identical / field-mismatch / CB-only / local-only**. Purpose: validate the field
mapping and crosswalks against real data, and preview exactly what an authoritative sync would change — the
decision to enable overwriting sync is gated on reviewing this report.

| Entity | Match key | Fields compared |
|---|---|---|
| Courses | `(course_no, revision_year→BE)` | name, name_th, credits, hours, is_gened, is_thesis |
| Programs | `program_code ↔ CB program_id` | names (via group), year_started, `alternative_program_code ↔ CB program_code` |
| Students | `student_id` | names (EN / `*_alt`=TH), sex↔gender, admission_year_be ↔ start_academic_year (CE→BE), status |
| Grades | `(student_id, course, year, semester, section)` | grade, credits |
| program_courses | `(program_code, course_no+rev)` | curriculum membership — validates the backfilled `ProgramCourse` join vs CB's authoritative curriculum |

- Output: per-entity bucket counts plus detailed field-level diffs. First delivery as a rake task / console
  report; a web report page is optional later.
- The `program_courses` row depends on the M:N re-model (this Project 1) existing — another reason it runs after.
- **Read-only** — no inserts/updates/deletes. It informs the "Join reconciliation" and "Managed-vs-local"
  questions below.

## Open questions for Project 2 (not this branch)

- **Unmapped-program policy:** CB returns many programs (long 12-digit `program_id`s) with no CP
  `program_code` — skip / null / placeholder + log?
- **Join reconciliation:** how the sync treats backfilled `ProgramCourse` rows ChulaBooster doesn't know
  about — full re-pull vs. delete handling (hard deletes are not observable in deltas).
- **`course_type` enum:** meaning is undocumented — confirm with the server team.
- **Service account** provisioning (see capabilities note above).
- **Managed-vs-local field ownership** per model (which attributes the sync overwrites vs. preserves).
