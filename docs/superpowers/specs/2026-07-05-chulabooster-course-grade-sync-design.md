# ChulaBooster Course + Grade Sync (Project 2, Phase 2b) — Design

**Date:** 2026-07-05
**Status:** Design approved (2026-07-05).
**Depends on:** Phase 2a (`Chulabooster::StudentSync`, `docs/superpowers/specs/2026-07-05-chulabooster-student-sync-design.md`) — students must be synced first; grade rows reference them. Program/status policy background: `docs/chulabooster-program-crosswalk.md`, `docs/chulabooster-student-status-crosswalk.md`. Unlike Phase 2a, the crosswalk evidence for courses and grades is small enough to live in this spec (see "Crosswalk evidence" below) rather than in standalone docs.

## Why

After the Phase 2a student import, the remaining CB-vs-local gap is enrollments and the course
catalog: the reconciliation counted ~36k CB-only `student_courses` rows and 180 CB-only courses.
Session analysis against the 2026-07-03 snapshot (post-student-import DB) refined those counts —
see "The landscape" below. Beyond the missing rows, the same analysis confirmed the Phase 2a
lesson repeats here: where local and CB both hold real data they agree almost perfectly, and
where they differ, **local is the stale side** (auto-generated course shells; interim grade codes
from an older registrar export). So Phase 2b is not additive-only: like the Phase 2a status
corrections, it detects stale local data and corrects it under `COMMIT=1`, fully audited.

Vocabulary as in Phase 2a: *sync* = authoritative-source reconciliation (`Chulabooster::*Sync`),
*import* = file-based (`Importers::*`).

## The landscape (2026-07-03 snapshot, DB after Phase 2a import)

CB `student_courses`: 49,502 rows total.

Disjoint buckets (sum = 49,502):

| Bucket | Rows | Disposition |
|---|---|---|
| Matched local grade, identical values | 15,402 | nothing to do |
| Matched, values differ (`value→value`) | 22 | **correct** (non-manual) / report (manual) |
| Sentinel `course_id` (`FOR_ETL`) | 1 | skip + count |
| Unknown student (non-dept, not in CB students export) | 3,876 | skip + report CSV |
| CB-only, course exists locally | 16,612 | create grade |
| CB-only, course in CB courses export | 11,817 | create grade (course created by CourseSync) |
| CB-only, course_no known at another revision | 60 (20 distinct courses) | create grade via ladder "copied" course |
| CB-only, course unknown both sides | 1,712 (145 distinct courses) | create grade via ladder placeholder |

"Matched" uses the revision-insensitive key (below); the 15,424 matches include 2,181 rows whose
local grade links to a *different course revision* — naive full-key matching would have imported
those as duplicate enrollments.

CB `courses`: 262 rows. 82 match locally (65 real + 17 local placeholder shells), 180 CB-only.
471 local courses are unknown to CB (untouched — additive-only). The 1,712 unknown-course grade
rows reference 145 distinct courses, almost all outside the department (5500 = language institute,
0295/0299 gen-ed, 2102 EE, …). Local practice already tracks outside courses (45% of existing
grades are on non-2110 courses), so these get placeholder rows, consistent with the CSV
`GradeImporter` convention.

Grade values: every CB grade value falls inside the local `Grade::GRADES` enum. 3,657 CB-only
rows have a **blank grade** — in-progress enrollments, almost all academic year 2025.

## Crosswalk evidence (why the correction policy is safe)

Method identical to the program/status crosswalks: match by business key, compare field-by-field.

**Courses** — matched on `(course_no, revision_year_be)`, 82 matches:
- Local real rows (`auto_generated: "none"`): **65/65 identical to CB on every compared field**
  (name, name_th, credits, l_credits, l_hours, nl_hours, s_hours, is_thesis, is_gened).
- The 17 "changed" rows are all local `auto_generated: "placeholder"` shells (name = course_no,
  every other field nil) vs CB's full registrar metadata. Missing data on our side, not divergence.

**Grades** — matched on `(student_id, course_no, year_ce, semester)`, 15,424 matches:
- **15,402 identical (99.86%)**, including all 2,181 revision-shadowed matches.
- The 22 diffs are predominantly local interim codes (`M`, `I`, `X`, `S`) vs CB's resolved final
  grade (`F`, `C`, `B`, `A`) — the stale-snapshot asymmetry again. A few are not mechanically
  explainable (`A`→`S`, `S`→`B`, `C`→`B`), but CB *is* the registrar: for `imported`-source rows
  its current value is the official transcript.
- Zero diffs involve `manual`-source rows. Zero `nil→value` or `value→nil` cases today.
- `credits_grant` agrees **100%** wherever grades agree.
- Zero local key collisions under the revision-insensitive key (no two local grades share
  student/course_no/year/semester across revisions).

## Core policy

1. **Local is authoritative; CB is additive — except where local data is known-stale.** The two
   known-stale classes, both corrected under `COMMIT=1` with audit CSVs:
   - **Auto-generated course shells** (`auto_generated` ≠ `"none"`): backfilled from CB metadata.
   - **Non-`manual` grade values** on matched enrollments: corrected to CB's value (CB is the
     registrar of record; evidence above).
2. **`manual` rows are never modified** — human-authored data wins; diffs are report-only.
3. **Never delete; never blank a value.** `value→nil` (CB blank, local graded) is report-only.
   Local-only grades (15,655) and local-only courses (471) are untouched.
4. **Existing grades are never re-linked** to a different course revision; only values change.
5. **Dry-run by default.** `COMMIT=1` is the only write gate; dry-run computes everything and
   writes report CSVs only (Phase 2a pattern).

## Components

### 1. `Chulabooster::CourseSync` (app/services/chulabooster/course_sync.rb)

A pure mirror of CB's `courses` export (262 rows). Runs **before** GradeSync. For each CB row,
match local `Course` on `(course_no, Convert.ce_to_be(revision_year))`:

- **CB-only → create** with full metadata: `name` ← `course_name`, `name_th` ← `course_name_alt`,
  `credits`/`l_credits`/`l_hours`/`nl_hours`/`s_hours` ← `Convert.int_or_nil` (CB sends floats),
  `is_thesis`/`is_gened` ← `Convert.bool` (`is_thesis`, `gened`), `auto_generated: "none"`
  (complete registrar metadata — not a shell), no program links (CB program identity is too
  coarse to map through the twin pairs; the M:N model permits program-less courses).
  `nl_credits` and `description` stay nil (CB doesn't export the former; the latter is null
  throughout the export).
- **Matched + local shell (`auto_generated` ≠ `"none"`) → backfill**: write the same field set,
  flip `auto_generated` to `"none"`. Audit CSV records old→new per field. (17 rows today; also
  the self-healing half of the loop — placeholders created by GradeSync's ladder get enriched by
  the next CourseSync run once CB exports the course.)
- **Matched + local real row, any compared field differs → report-only** (`course_discrepancies.csv`,
  expected empty today).
- Idempotent: re-run after COMMIT matches everything, writes nothing.

### 2. `Chulabooster::GradeSync` (app/services/chulabooster/grade_sync.rb)

Streams CB `student_courses` (49,502 rows) against in-memory local indexes (students by
`student_id`, grades by identity key, courses by `(course_no, rev_be)` — same scale as
StudentSync's indexes).

**Identity key: `(student_id, course_no, year_ce, semester)` — revision-insensitive.**
`course_no` is the project's cross-revision course identity (CLAUDE.md); validated by zero local
collisions and by the 2,181 revision-shadowed matches that full-key matching would duplicate.

Row walk, in order:

1. `course_id` not matching `/\A\d{4}\d+\z/` (e.g. `FOR_ETL`) → skip, count. (1 row.)
2. Student unknown locally → skip + `skipped_unknown_students.csv` (student_id, course, term,
   grade). These are non-department students absent from CB's own students export — no name or
   program available, so no Student row can be built. (3,876 rows / 2,920 students.)
3. **Matched** local grade:
   - Values equal (grade **and** `credits_grant`) → count only.
   - Local `source == "manual"` and values differ → `grade_discrepancies.csv`, no write.
   - CB grade blank, local has a value (`value→nil`) → `grade_discrepancies.csv`, no write.
   - Otherwise (`value→value`, or `nil→value` fill on a previously-ungraded enrollment) →
     **correct**: set `grade` ← CB value, `grade_weight` ← `GRADE_WEIGHTS[grade]` (nil for
     non-letter grades), `credits_grant` ← `Convert.int_or_nil` (CB's grade is always non-blank
     in this branch, so no in-progress-zero hazard). Audit `grade_corrections.csv`
     (old/new values, source). 22 rows today; steady-state this is how each semester's
     in-progress enrollments get their final grades on the next run.
4. **CB-only** → resolve course, then create `Grade`:
   - Course resolution ladder: exact `(course_no, rev_be)` → else closest local revision,
     duplicated as `auto_generated: "copied"` → else minimal placeholder
     (`name` = course_no, `auto_generated: "placeholder"`, no program links). Reimplements the
     CSV `GradeImporter` ladder without its latent `program:` bug. In dry-run, ladder courses are
     recorded in `ladder_courses.csv` but not created; grade validity is simulated against the
     would-create course.
   - Grade attributes: `grade` (blank → nil), `grade_weight` ← `GRADE_WEIGHTS[grade]`,
     `credits_grant` ← `Convert.int_or_nil`, **forced nil when grade is blank** (CB reports `0.0`
     for in-progress enrollments, which would misread as "earned 0"), `year_ce` ←
     `academic_year` (already C.E. — do NOT convert), `semester` ← `Convert.semester_number`,
     `source: "chulabooster"`, `section: nil`.
   - Validation failure → `row_errors.csv`, run continues.

Duplicate CB rows for the same identity key within one run: first wins, subsequent rows are
counted + reported (`row_errors.csv` with reason `duplicate CB row`), not written.

### 3. Model change: `Grade` source `"chulabooster"`

`Grade::SOURCES` gains `"chulabooster"`; `SOURCE_ICONS` gains an entry (e.g. `"sync"`). If any
view renders source badges, add a `.badge-*` class per the UI conventions (checked at
implementation time). Distinguishes CB-synced rows from CSV imports permanently and scopes future
correction logic precisely. No migration — all written fields already exist.

### 4. Rake tasks (lib/tasks/chulabooster.rake)

- `chulabooster:sync_courses` → run dir `tmp/chulabooster_sync_courses/<ts>`
- `chulabooster:sync_grades` → run dir `tmp/chulabooster_sync_grades/<ts>`

Both: dry-run default, `COMMIT=1` to write, `SNAPSHOT_DIR=` for offline runs, counts summary
printed like `sync_students`. `sync_grades`'s description notes that `sync_courses` should run
first (not enforced — the ladder makes out-of-order runs safe, just noisier).

### 5. Drive-by fix: CSV `GradeImporter` placeholder branch

`resolve_course` / `resolve_course_by_no` still call `Course.create!(program: Program.placeholder)`;
`Course` lost `program=` in the M:N remodel, so the totally-unknown-course branch appears broken.
Verify, fix to create program-less courses (as GradeSync does), regression-test.

## Report files

| File | Task | Contents |
|---|---|---|
| `created_courses.csv` | courses | 180 CB-only courses created |
| `backfilled_courses.csv` | courses | shell backfills, old→new per field (17) |
| `course_discrepancies.csv` | courses | real-vs-real diffs, report-only (expected 0) |
| `created_grades.csv` | grades | ~30k created grades |
| `grade_corrections.csv` | grades | value corrections + nil-fills, old→new (22 today) |
| `grade_discrepancies.csv` | grades | manual-row + `value→nil` diffs, report-only |
| `skipped_unknown_students.csv` | grades | 3,876 non-dept-student rows |
| `ladder_courses.csv` | grades | copied/placeholder courses created (or would-create) |
| `row_errors.csv` | both | validation failures, duplicate CB rows |

## Error handling

Per-row rescue/validation-failure → `row_errors.csv`, run continues (StudentSync pattern). Grade
values outside `Grade::GRADES` fail model validation into `row_errors.csv` (zero today). Malformed
`course_id` skipped and counted. No partial-write hazard beyond Phase 2a's (row-at-a-time saves;
re-run converges).

## Expected production outcome (vs. 2026-07-03 snapshot)

+180 courses (full metadata) + 145 placeholder + 20 copied courses via the ladder; 17 shells
backfilled; 30,201 grades created (less any row errors); 22 grades corrected; 3,876 rows skipped
to CSV; 15,655 local-only grades and 471 local-only courses untouched.
Run order: fresh snapshot → `sync_students` (keeps students current) → `sync_courses` →
`sync_grades`, dry-run review before each `COMMIT=1`.

## Testing

Written after implementation (project preference), discussed before writing per CLAUDE.md.
Planned coverage, fixture-based like Phase 2a's 15 tests:

- **Bucket routing** (GradeSync): matched-identical, manual-diff→report, `value→nil`→report,
  `value→value`→correct, `nil→value`→fill, unknown student→skip, CB-only→create,
  sentinel/duplicate rows.
- **Write-gate invariants**: dry-run leaves Course/Grade counts and all attributes untouched for
  both services (the Phase 2a invariant tests).
- **CourseSync**: create with type coercions, shell backfill (+ `auto_generated` flip),
  real-row diff → report not write, idempotence.
- **Ladder**: exact / copied / placeholder branches; dry-run simulation doesn't persist.
- **Value rules**: blank grade → nil grade + nil `credits_grant`; `grade_weight` derivation
  incl. non-letter grades; `year_ce` not era-converted; `semester_number` parsing.
- **Regression**: GradeImporter placeholder-branch fix.

## Out of scope

`program_courses` links (CB identity too coarse; reconcile already reports them), section
assignment (CB `section` is null), deleting/re-linking anything, scheduled runs, the CSV
`DataImport` UI flow, and correcting the 22 grade diffs' odd cases beyond CB's value (any human
override happens after reviewing `grade_corrections.csv`).
