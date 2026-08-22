# CS Study Track (ภาคนอกเวลาราชการ) + Dissolving Program 0999

**Date:** 2026-08-21
**Status:** Approved (option C1 of the alternatives considered)

## Background

The department's M.Sc. Computer Science program ran two parallel tracks:

- **Regular** (ภาคปกติ / in-time), intakes since B.E. 2514.
- **Special** (ภาคนอกเวลาราชการ), the department's "CT" cohorts, intakes B.E. 2533–2560.
  CT = นอกเวลาราชการ is confirmed by department hard-copy records.

The database currently blends both tracks inside the CS program group with no
distinguishing field, and ~730 students (everyone admitted 2540–2556) sit on
program row `0999` — a **synthetic program code** that appears in no import
file, no ChulaBooster (CB) field, and no registrar data. It was hand-seeded in
March 2026 and both import pipelines assigned students to it purely by the
"latest revision started ≤ admission year" rule.

### Evidence established before this design (2026-08-19 → 21 investigation)

- Regular CS curriculum lineage (local code / year started B.E. / CB row, CB
  `major_code=21101`, degree lineage 175): `1027`/2524, `0038`/2538,
  `2205`/2557, `3626`/2561, `4242`/2566. **There is no regular revision at
  B.E. 2540.**
- CB has exactly one extra row in that degree lineage: `175211001997`
  (revision 1997 CE = B.E. 2540, `major_code=21100`, blank name) — the special
  program's own curriculum registration. Local `0999` (B.E. 2540, 48 credits)
  corresponds to it, but the 4-digit string "0999" itself is our invention.
- Per-student track classification is recoverable from three independent,
  mutually-agreeing signals:
  - CB students export: `project` (`201` = regular study plan, `212` =
    special) + `fee_type` (`1`/`01` regular, `4`/`04`/`07` special). Perfect
    partition of CS-group students for intakes 2533–2553; the split appears
    exactly at 2533 (the special program's first intake).
  - Student ID digits 3–4 for the 10-digit era: `70` = regular, `71` =
    special (last special intake 2560). Fee/project blur from 2554 onward
    (regular program went special-fee), so the segment is the marker there.
  - `students.enrollment_method` already holds the department's own label
    `"โครงการภาคนอกเวลาราชการ"` for 719 students (CS 379, SE 283, CM 57),
    agreeing with the CB classifier 717/719.
  - Cross-validated against the 30th-anniversary book's CT01–CT16 alumni
    lists: 675/684 agree; all 9 conflicts side with the classifier.
- Both import pipelines **overwrite** `program_id` on upsert
  (`Base#execute`: `existing.assign_attributes(attrs.except(*unique_key_fields))`),
  so any data correction would be clobbered by the next re-import unless
  guarded.

## Decision (what and why)

Represent the track as a **student-level field** and **dissolve `0999`**:

1. `students.study_track` — nullable string, `"regular"` / `"special"`.
   Null = unknown or not applicable (e.g. bachelors, unclassified eras).
2. Backfill it from the evidence above (dry-run first, human-reviewed).
3. Re-assign the 730 students on `0999` to the correct **regular** revision by
   admission year (all fall in 2540–2556 → `0038`), then delete the `0999`
   Program row and its seed entry.
4. Guard the student importer so upserts never overwrite an existing
   program assignment (fill-blank-only, mirroring the CB sync policy
   "local program assignment is authoritative").

Why not a `CT` ProgramGroup (option A): a group would buy CT-generation
notation, but costs a permanent CS+CT union in every "all CS masters" query,
and misstates 2533–2539 (those special students studied under the *shared*
curricula 1027/0038 — the track was administrative, not curricular, until
2540). Why not keeping `0999` as "the special row" (option B / C2): a parallel
program is not a *revision*, so every "latest revision ≤ year" resolver would
need to special-case it forever, and the synthetic code would stay
load-bearing. The flag records exactly who is special, so option A (or a real
special-program row, if its official codes ever surface) remains reachable
later without information loss.

Accepted limitations (documented, not blockers):

- Special 2540+ students' `program_id` points at `0038` — a documented
  approximation; their true registration is CB `175211001997`, which has no
  local Program row. The crosswalk doc records this.
- CT-generation notation (CT14 ↔ B.E. 2546) stays unsupported.
- CS students with ID segment `72` (2562+) are a different, unidentified
  track — left null.
- SE/CM special tracks exist (label data proves it) but their CB "twin"
  program-row pairs don't split cleanly along the label; SE/CM get the label
  pass only. Twin semantics are a separate future investigation.

## Components

### 1. Migration + model

- `add_column :students, :study_track, :string` (no index — the students
  index DataTable filters client-side).
- `Student::STUDY_TRACKS = %w[regular special].freeze`
- `Student::STUDY_TRACK_ICONS = { "regular" => "light_mode", "special" => "dark_mode" }.freeze`
  (day program vs evening program), per the domain-icon convention.
- Validation: `inclusion: { in: STUDY_TRACKS }, allow_nil: true`.

### 2. UI

- Student show page: detail row "Study Track", rendered as a badge —
  data-driven class `badge-track-#{study_track}`; two new frosted badge
  classes `.badge-track-regular`, `.badge-track-special` in
  `application.scss`. Display labels: regular → "Regular", special →
  "นอกเวลาราชการ". Blank row omitted when null.
- Students index: `study_track` column with a select filter, following the
  existing degree-level column+filter pattern. Badge rendering, blank for
  null.
- Student form (admin edit): select with `options_for_select` + `data-icon`
  from `STUDY_TRACK_ICONS`, blank option allowed (null = unknown).
- Check `docs/backlog.md` triggered items for the show-page change.

### 3. Backfill task — `students:backfill_study_track`

`lib/tasks/students.rake`. Dry-run by default, `COMMIT=1` to write,
`SNAPSHOT_DIR=` to use the CB snapshot instead of the live client (same
contract as the `chulabooster:*` tasks). CB students export is fetched once
and indexed by `student_id`.

Classification rules, in order (first hit wins; later rules never override
an earlier assignment):

1. **Label pass (all groups):** `enrollment_method == "โครงการภาคนอกเวลาราชการ"`
   → `special`.
2. **CS group, intakes 2533–2553:** from the CB row:
   `project == "212"` and `fee_type` in `%w[4 04 07]` → `special`;
   `project == "201"` and `fee_type` in `%w[1 01]` → `regular`;
   any other combination → review CSV, left null.
3. **CS group, intakes 2554–2560:** student ID digits 3–4:
   `"71"` → `special`; `"70"` **plus CB plan `project == "201"`** →
   `regular`; anything else → review CSV, left null.
   *(Amended 2026-08-22 during execution: the first dry-run surfaced 41
   students the dept label marks special who carry 70-range IDs — after
   2554 the 71 range stops being reliably issued, so a bare 70-range ID
   proves nothing and "regular" needs plan-201 corroboration. The original
   rule "`70` → regular" over-claimed.)*
4. **CS group, intakes ≤ 2532:** `regular` (the special program did not yet
   exist).
5. Everything else (CS 2561+, unlabeled SE/CM, other groups): left null.

Conflict rule: if the label pass and the CB classifier disagree for the same
student, assign nothing and emit a review-CSV row (per the 2026-08-20
validation there are no such students today; the rule is a tripwire, not a
path).

Outputs under `tmp/study_track_backfill/`: `assignments.csv`
(student_id, name, group, year, track, evidence), `review.csv` (unclassified
or conflicting rows with all raw signals), and a console summary
(counts per group × year × track).

### 4. Dissolution task — `programs:dissolve_0999`

Same dry-run/`COMMIT=1` contract. For each student on program `0999`:
re-assign to the latest CS-group program with
`year_started_be <= admission_year_be`, **excluding `0999` itself** (for the
actual population, 2540–2556, this is always `0038`; the general rule is
defensive). Prints per-year reassignment counts. After zero students
reference it, destroys the `0999` Program row (abort with a clear message if
any reference remains). Run order: backfill first, dissolve second — not
load-bearing (classification keys on program *group*), but keeps the review
CSVs on stable data.

Seeds (`db/seeds/programs.rb`): remove the `0999` entry; leave a comment in
its place stating that the B.E. 2540 registration is the special program
(CB `175211001997`), represented by `students.study_track`, so nobody
re-adds it as a revision.

### 5. Importer guard

`Importers::Base#execute` upsert path gains a hook:
`attrs.except(*unique_key_fields, *update_protected_fields(existing))`, with
`update_protected_fields(_existing) = []` in Base.
`StudentImporter` overrides it: `[:program_id]` when
`existing.program_id.present?` (the pipeline stores the resolved program as
`attrs[:program_id]` — `student_importer.rb:216,228`). Note the transform also
sets `attrs[:program_id] = nil` when a mapped program value fails to resolve;
the guard must strip the key either way so an unresolvable value cannot null
out an existing assignment. Effect: files can fill a blank program but never
change an assigned one. Update the `program_name` attribute `help:` text to
say so. `study_track` gets **no** importer attribute definition, so imports
can never touch it.

### 6. Documentation

- `docs/chulabooster-program-crosswalk.md`: add the `175211001997` finding
  (special program registration, no local Program row, represented by
  `students.study_track`), the fee/project/segment classifier, and the open
  SE/CM twins question.
- `CLAUDE.md` Data Model Conventions: one bullet for `study_track` (meaning,
  null semantics, backfill provenance, importer-invisible).
- Memory/backlog: the ~56 CT alumni missing from the DB stay parked with the
  book add-missing policy (out of scope here).

## Testing (candidates — final list to be agreed after implementation)

- Model: `study_track` validation (valid values, nil allowed, junk rejected).
- Importer guard: upsert with a mapped program column does not change an
  existing student's program; does fill a blank one; create path unaffected.
- Backfill classifier: unit-test the rule function against synthetic CB rows
  (each rule, the conflict tripwire, the ≤2532 default, the null cases).
- Dissolution: reassignment picks `0038` for a 2540s student; task aborts if
  a student would be left pointing at `0999`.

## Rollout

1. Dev: migrate → backfill dry-run → review CSVs (dae) → `COMMIT=1` →
   dissolve dry-run → `COMMIT=1` → UI/manual spot checks.
2. Production: deploy (migration included; no job-side code → no
   solid_queue restart), then run the same two tasks with the same
   dry-run-review-commit rhythm. CB is reachable from prod (live client) or
   use a fresh snapshot.
3. Verify: `Program.find_by(program_code: "0999")` is nil; 0038 student
   count grew by the dissolved population; `study_track` distribution
   matches the dry-run summary (~700 special in CS + 719 labeled across
   CS/SE/CM, overlapping).

## Out of scope

- Adding the ~56 book-only CT alumni (blocked on the add-missing policy:
  placeholder student IDs, English-name policy).
- SE/CM twin program-row semantics; CS segment-72 track identification.
- CE program identification (666 book names); book-driven name rechecks.
