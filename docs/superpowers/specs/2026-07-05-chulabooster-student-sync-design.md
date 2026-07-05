# ChulaBooster Student Sync (Project 2, Phase 2a) — Design

**Date:** 2026-07-05
**Status:** Design approved (2026-07-05), including the review-revised majority-enrollment
twin default and the `sync_students` task name (chosen to scale to a future sync family:
`sync_courses`, `sync_grades`, … as later Project-2 phases arrive).
**Depends on:** `docs/chulabooster-program-crosswalk.md` and
`docs/chulabooster-student-status-crosswalk.md` — every heuristic and policy below is derived and
validated there; this spec does not restate the evidence.

## Why

The reconciliation dry-run (Phase 1) found **1,441 students CB has that we don't** — mostly
historical (62.7% admitted before 2010). This phase brings them in. It is the **first write path**
from CB into the local DB, so it is deliberately narrow: create missing students only. Naming
follows the project's vocabulary split: *import* = file-based (`Importers::*`), *sync* =
authoritative-source reconciliation — hence `Chulabooster::StudentSync`, not a new `Importer`.

## Scope

**In:** creating local `Student` records for CB-only students; two report-only discrepancy checks
on existing students; a `cb_status_code` column; populating `Program.alternative_program_code`;
a rake task; a minimal admin pointer page.

**Out:** creating/updating `Program` records (resolve-only — user decision); updating any field on
existing students (except the new, previously-empty `cb_status_code`); courses/grades sync;
scheduled runs; the CSV `DataImport` UI flow (wrong grain for an API source).

## Core policy (from the crosswalk docs — binding)

1. **Authority is per-field.** Program identity: local is authoritative, CB is coarser. `status`:
   CB is more reliable (local `"active"` is stale-biased).
2. **Existing records are never modified** — with the single exception of `cb_status_code`, which
   has no local equivalent to overwrite.
3. **Every guess is flagged, never silently trusted**: heuristic group assignments, twin-tie
   defaults, and 7-digit-ID defaults all write an explanatory note to the student's `remark`.
4. **Discrepancies are reported loudly, corrected by humans** — the confirmed CM/CD case (two
   students where the heuristic was wrong and local was right) is the standing proof of why.

## Components

### 1. Prerequisite data task: populate `Program.alternative_program_code`

Set `alternative_program_code` = CB `major_code` for all 45 non-placeholder programs, **in
`db/seeds/programs.rb`** (programs are seed-managed): `21101` on all CS revisions, `21102` SE,
`21104` CEDT, `21100` on CP/CM/CD. Re-seed to apply. This makes resolution a DB query
(`Program.where(alternative_program_code: major_code)`) instead of a Ruby constant.

### 2. `Chulabooster::StudentSync` (app/services/chulabooster/student_sync.rb)

Sibling of `Reconciler`; takes a `Client` or `SnapshotClient`. Two passes:

**Pass 1 — create missing students.** For each CB student not in the local DB (by `student_id`),
resolve a program and build a `Student`:

*Layer A — group:*
- `major_code` `21101/21102/21104` → CS/SE/CEDT directly.
- `21103` → unresolvable (no local group; skip + report).
- `21100` → student_id segment heuristic (positions 2–3 of 10-digit IDs: `70|72`→CM, `71|73`→CD,
  else→CP; 7-digit IDs→CP — all 442 known 7-digit students are CP). Then the **year-existence
  fallback**: if the guessed group has no program with `year_started_be <= admission_year_be`,
  fall back to the alternate candidate (validated 146/146 on segment 71).

*Layer B — revision:* programs in the group with `year_started_be <= admission_year_be`, take the
max year. Ties (twin pairs) → **majority-enrollment default**: the twin with the most current
local students; lower `program_code` only when all twins are empty. (Confirmed by the user
2026-07-05, replacing the earlier "lower code" choice after review showed lower-code picks the
minority — or an empty program — in ~6 of 13 pairs, worst case 0 vs 604 students.)

Note on 7-digit IDs: resolution still runs for them — majors `21101/21102/21104` resolve by
`major_code` alone regardless of ID format. Only the **segment heuristic step** is inapplicable,
so 7-digit + `major_code=21100` (23 students) defaults to CP with a `remark` flag.

*Field mapping:* `student_id`, `firstname/lastname`→`first_name/last_name`,
`firstname_alt/lastname_alt`→`*_th` (strip trailing whitespace — CB pads names),
`gender`→`sex`, `start_academic_year+543`→`admission_year_be`, resolved program →`program`,
`student_status`→`cb_status_code` (raw) **and** →`status` via the family table (`00/01/05`→active,
`11/12/13`→graduated, `21–39` family→retired; unknown code→`unknown` + report line).
`remark` gets an audit note whenever Layer A used the heuristic, the 7-digit default, the
fallback, or a twin tie — one sentence naming what was assumed. All other fields left blank.

**Pass 2 — discrepancy reports (no write path, by construction).** For every *matched* student:
- *Program:* CB-implied group (same Layer A, **including** the year-existence fallback) vs.
  actual local group → mismatch rows to `students_program_discrepancies.csv`. Expected rows
  today: **0** — the only two known group-level disagreements (the confirmed-CM pair) are
  exactly the cases the fallback resolves, and the fallback must fall back to the *other
  graduate group* before bachelor (CD→CM→CP) or it would mis-resolve them to CP. The report
  exists to catch future divergence.
- *Status:* CB code family vs. local `status`, flagging stale-`active` (expected ~765 rows) →
  `students_status_discrepancies.csv`.
- Also: refresh `cb_status_code` on matched students (the one permitted write; only in COMMIT mode).

### 3. Migration

`add_column :students, :cb_status_code, :string` (nullable, no index needed yet).

### 4. Rake task (lib/tasks/chulabooster.rake)

`bin/rails chulabooster:sync_students` — **dry-run by default**: computes everything, writes
report CSVs to `tmp/chulabooster_sync/<ts>/`, prints a summary (creatable / flagged-heuristic /
flagged-twin / unresolvable / discrepancy counts), writes **nothing** to the DB.
`COMMIT=1` re-runs the same computation and creates the students (+ `cb_status_code` refresh).
`SNAPSHOT_DIR=` supported, same as `reconcile`. Console output mirrors `reconcile`'s style.

### 5. Admin pointer page

`/chulabooster` (admin-only, follows `require_admin` convention): a static card explaining what
the sync does, the exact rake commands, and links to the two crosswalk docs. No trigger button —
deliberate, per user decision (console-first at this maturity; personal-account creds).

## Expected outcomes (simulated against the real 2026-07-03 snapshot)

1,432/1,441 resolve (CS 686, CP 229, SE 220, CM 215, CD 62, CEDT 20); 506 heuristic-flagged;
328 twin-flagged; 23 seven-digit-ID defaults; 9 unresolvable (all `21103`); statuses
944 retired / 464 graduated / 33 active. The implementation's dry-run must reproduce these
numbers against the same snapshot — that is the acceptance test of the resolution logic.

## Error handling

- Unknown status code → `status: "unknown"` + report line (never crash the run).
- Missing/blank `start_academic_year` → unresolvable bucket (none observed, but guard).
- Duplicate `student_id` race (created between dry-run and COMMIT) → `find_by` guard, count as
  skipped, not error.
- Validation failure on a built `Student` → row error in the report, run continues (mirrors
  `Importers::Base` row-error semantics).

## Testing

Per project convention (tests after implementation, discussed first — see CLAUDE.md): planned
coverage is resolution-logic unit tests (each Layer A/B branch incl. fallback + twin default),
a fixture-based end-to-end dry-run/COMMIT pair asserting created counts and that dry-run writes
nothing, and discrepancy-report tests seeded with a known-stale student. To be confirmed with
the user before writing.
