# ChulaBooster Student Status Crosswalk

**Status:** Findings from designing the write-back student importer (Project 2, Phase 2a — not
yet built). See `docs/chulabooster-program-crosswalk.md` for the companion analysis of program
identity, and `docs/superpowers/specs/2026-07-01-chulabooster-reconciliation-design.md` for the
read-only reconciliation dry-run this all builds on.

## The headline finding: for `status`, authority is flipped

For program identity, local data is authoritative and CB is coarser (see the program crosswalk
doc). For `Student#status`, **it's the other way around: CB is the more reliable source, and our
local data has a known staleness bias.**

Why: locally, `status` defaults to `"active"` at creation (`t.string "status", default:
"active"`) and there is no process that re-imports a student purely to update their status —
we only ever get fresh CSV/Excel exports for *new* students, not "this existing student's status
changed" updates. So a local `status: "active"` doesn't mean "confirmed still enrolled" — it
means "nobody has told us otherwise since we imported them." That's silence, not a signal. CB, as
the live registrar system, presumably reflects real enrollment status continuously.

## Getting the validation methodology right (this took a wrong turn first)

The first pass measured "how often does CB's raw `student_status` code match the student's
*local* status" and got a discouraging, noisy answer (roughly 55–95% depending on the code) —
**but that was measuring the wrong thing.** It implicitly treated local status as ground truth,
including the `"active"` bucket, which is exactly the bucket known to be stale.

**Correct approach: only validate against local labels that require an actual human decision to
set** (`graduated`, `retired`) — not the default/silent ones (`active`, `unknown`). Checked
against all 7,135 matched students:

| local status | CB code family | accuracy |
|---|---|---|
| `graduated` | `11`, `12`, `13` | **99.9%** (3,496 / 3,498) |
| `retired` | `21,23,24,25,27,28,30,31,32,33,35,36,37,39` | **98.1%** (516 / 526) |

Once measured correctly, CB's status code is highly reliable — the earlier noisy number was an
artifact of a flawed validation, not evidence that CB's encoding is unreliable.

## The payoff: quantifying the local staleness

The reverse check is the concrete result: of the **2,337 locally-`"active"` students** matched to
CB, only 67.3% have a CB code consistent with still being active. The rest:

- **25.9% (605 students)** have a CB code implying they're actually **graduated**.
- **6.8% (160 students)** have a CB code implying they're actually **retired**.
- Combined: **32.7% (765 students)** are very likely mislabeled `"active"` locally right now.

This is a real, sizeable existing data-quality gap, independent of the new-student importer —
CB's data surfaces it, but fixing it is a separate decision (see below).

## Status code family (empirically derived, not documented anywhere by CB)

| CB `student_status` prefix | meaning |
|---|---|
| `00`, `01`, `05` | active |
| `11`, `12`, `13` | graduated |
| `21`–`39` (`21,23,24,25,27,28,30,31,32,33,35,36,37,39`) | retired |

The leading digit(s) appear to encode a broad category; the full code likely carries a finer
reason within that category (e.g. different retirement reasons, or graduation with/without
honors) that our 5-value `Student::STATUSES` enum can't represent — see below.

## Design decisions for the importer

1. **New students**: derive `status` from the code family above with real confidence (no need to
   fall back to `"unknown"` — that was the right call under the flawed validation, not anymore).
2. **Preserve CB's finer resolution**: add a new column, `cb_status_code` (raw string, e.g.
   `"13"`), storing CB's code verbatim rather than collapsing it into our coarser enum and
   discarding the rest. Since no local field currently occupies this, populating/refreshing it is
   safe for **every** student the importer touches — new and already-existing alike. This is not
   "overwriting authoritative local data" (there's no local equivalent to overwrite), just
   mirroring what CB currently reports.
3. **Existing students — a second discrepancy report, parallel to the program-identity one**: for
   every already-matched student, compare their local `status` against what CB's code family
   implies. Any student whose local `status` looks stale (most importantly, `"active"` locally
   but CB implies otherwise) goes into a dedicated report (e.g.
   `students_status_discrepancies.csv`) and a loud console summary line.
4. **Report only — never auto-correct, even at 99% confidence.** A status change (especially to
   `"graduated"`) has real downstream consequences (degree conferral, reporting, access). The
   importer's job is to surface the ~765 likely-stale records for a human to confirm and fix, not
   to silently reclassify them. This follows the same non-destructive principle established for
   program-identity discrepancies: CB being *probably* right isn't the same as CB being
   *confirmed* right for a specific record.

## Why this doesn't contradict the program-identity findings

Two different fields, two different authorities, for a structural reason: **local is authoritative
for what local actually tracks carefully** (program assignment — we maintain per-revision detail
CB literally cannot represent) **and CB is authoritative for what CB tracks live and we don't**
(ongoing enrollment status — we only get point-in-time snapshots at import time). The general
rule isn't "trust local" or "trust CB" — it's "trust whichever system's *process* actually
maintains that specific field over time," checked empirically per field rather than assumed.
