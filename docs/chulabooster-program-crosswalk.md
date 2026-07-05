# ChulaBooster Program Crosswalk

**Status:** Findings from the read-only reconciliation dry-run (Project 2, Phase 1). No write-back
sync exists yet — this document records what the dry-run revealed about how ChulaBooster (CB)
represents programs, so Phase 2 (the actual sync) is designed against verified facts instead of
assumptions. See `docs/superpowers/specs/2026-07-01-chulabooster-reconciliation-design.md` for the
dry-run's own architecture, and `docs/chulabooster-student-status-crosswalk.md` for the companion
analysis of `Student#status` — a field where, unlike program identity, **CB turns out to be more
authoritative than local data**, not less.

## The headline finding

Local `cp-api` and CB both ultimately trace back to the same university registrar data, but each
system **decorates** it differently — CB's program identifiers are coarser than ours, and the
apparent "mismatch" between the two is a crosswalk/coverage gap, not real data divergence. Verified
against a full snapshot of CB's `programs`, `students`, `program_courses`, and `student_courses`
exports (2026-07-03/04):

1. **CB's `program_id` is not our `program_code`.** CB's real `program_id` is a structured
   12-digit value: `degree_code(3) + major_code(5) + revision_year(4, CE)`. Only 2 of CB's 26
   program rows have a short `program_id` that happens to equal a local `program_code` (`3736`,
   `4784`) — these are manually-created bridge/test rows in CB (recent timestamps, the only 2
   rows with a populated `program_name`), not representative of CB's real catalog.
2. **CB's `program_name` is blank on all 24 "real" program rows** — no text available for
   name-based matching either.
3. **Local `Program.alternative_program_code`** — the field that looks designed to hold CB's
   crosswalk code — **is empty on all 46 local programs.** It was never populated.
4. **CB's `program_id` field on *student* rows is garbage**, not a usable program reference. Its
   only observed values across all 8,576 CB students: `nil` (1,554), `"GenId"` (4,970),
   `"MODCOURSE"` (1,851), `"MODPERIOD"` (201). The reliable field instead is `student.major_code`
   (100% populated, 5 distinct values, matching the `major_code` segment of the programs export).
5. **CB does not track our "twin" program pairs separately.** We have 13 cases where two (or
   four) local `Program` rows share the same `program_group` and `year_started_be`, differing
   only in `program_code` — regular/extension tracks, or (for CD) a credit-count split (60 vs 72,
   the standard Thai doctoral "entered with vs. without a master's" distinction). **CB has
   exactly one row for every one of these 13 cases**, regardless of whether we track 2 or 4 local
   variants for that year.
6. **`degree_code` behaves like a stable per-program-lineage identifier**, not a degree-level
   bucket: `233` → CP (7/7 of CP's revision years, 1976–2023, exact match), `235` → CM's earliest
   revisions, `387` → CD's earliest revision, `175` → CS's oldest revision (`0999`, from before CS
   had its own `major_code`). Every local revision year for CP/CM/CD has *some* corresponding CB
   row under `major_code=21100` — zero gaps — once the twin-collapsing in point 5 is accounted for.

**Conclusion: the reconciliation report's `24 cb-only / 44 local-only` program counts are a
crosswalk/coverage artifact, not evidence that the underlying programs disagree.** A
manually-authored crosswalk (`degree_code` → local `program_group` + track) would resolve the
large majority of it.

## Empirical major_code → program_group mapping (verified, 7,135 matched students, zero exceptions)

| CB `major_code` | local `program_group` | confidence |
|---|---|---|
| `21100` | shared: **CP** (bachelor), **CM** (master), **CD** (doctoral) | high, but ambiguous by itself — see below |
| `21101` | **CS** | exact, 1,024/1,024 matched students |
| `21102` | **SE** | exact, 673/673 matched students |
| `21103` | *(no local match — 9 CB students, none imported locally)* | coverage gap, not a mismatch |
| `21104` | **CEDT** | exact, 874/874 matched students |

`21100` needs `degree_code` (only present on CB's *programs* export, not the *students* export) to
disambiguate CP vs. CM vs. CD. See the `degree_code` findings above for what's known.

## Reproducing this analysis

The underlying data is **not** committed to version control (see below) — regenerate it with:

```
bin/rails chulabooster:snapshot                        # full CB pull, ~40 min (student_courses is the slow entity)
                                                        # resumable: RESUME=tmp/chulabooster_snapshot/<ts>
bin/rails chulabooster:reconcile SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts>   # instant, offline, no CB load
```

`app/services/chulabooster/snapshotter.rb` / `snapshot_client.rb` implement the snapshot cache (a
drop-in `Client` replacement reading cached JSONL instead of hitting CB). Once a snapshot exists,
any further analysis — reconciliation, ad hoc cross-tabs like the ones behind this document — runs
against it with **zero additional CB requests**.

**`tmp/` is `.hgignore`d** — the raw snapshot (JSONL, ~7 MB) and the reconciliation report CSVs are
not durable. This document captures the *conclusions*; regenerate the raw evidence with the
commands above if you need to re-verify or dig further.

## Policy for the eventual write-back sync (Project 2, Phase 2 — not yet built)

This dry-run exists specifically to de-risk write-back before it's built (see the Phase 1 design
doc's motivation). Given the findings above, the sync must follow these rules:

- **Local program/student data is authoritative and strictly more detailed than CB's.** CB cannot
  represent our twin-track pairs (regular/extension, credit-count splits) — it has exactly one
  registrar entry where we have two or four. The sync **must never overwrite** an existing local
  student's program assignment, or collapse/merge existing twin-pair `Program` rows, on the basis
  of CB data. CB's view is coarser, not more correct.
- **CB is additive-only**: its role is to bring in students CB knows about that we don't have
  locally yet (1,441 such students, per the 2026-07-03 reconciliation) — not to correct or
  overwrite what we already have.
- **New-student program assignment is ambiguous exactly where a twin pair exists.** When adding a
  student who is new to the local DB, CB's signal (`major_code`, admission year) narrows them to
  a `program_group` + `year_started_be`, but if that `(group, year)` has a twin pair (13 known
  cases), CB's data cannot say which of the pair they belong to. The sync needs an explicit,
  documented default (e.g. the more common variant) or a manual-review queue for exactly these
  cases — it cannot silently guess and treat the guess as authoritative.
- Populating `Program.alternative_program_code` with the crosswalk above (where confidence is
  high) is the natural next step to make this mapping queryable in code, rather than living only
  in this document.

---

## 4. Follow-up: CB cannot distinguish CM (master's) from CD (doctoral) — worked around, not fixed (2026-07-05)

While designing the write-back student importer, we hit a gap deeper than the twin-pair
ambiguity above: `major_code=21100` is shared by **three** local groups (CP bachelor, CM master,
CD doctoral), and the field that *would* disambiguate them — `degree_code` — **only appears on
CB's `programs` export, never on the `students` export.** A brand-new student's CB record alone
cannot say bachelor vs. master vs. doctoral.

**Every other CB student field was checked and rejected as a substitute:**

| CB field | result |
|---|---|
| `project`, `admission_type` | Cleanly split CP vs. {CM, CD} — but **share the same dominant codes** (`project="201"`, `admission_type="5"`) for **91% of graduate students**. No split between CM and CD. |
| `fee_type`, `concentration`, `study_program_system` | Uniform across CM/CD, or blank entirely. No signal. |

**The workaround: `student_id`'s own digit structure.** `student_id` is the join key — identical
in both systems, assigned once by the registrar, independent of anything CB exports. Positions
3–4 (0-indexed 2–3), checked across the full matched population:

| group | segment values | coverage |
|---|---|---|
| CP | `30`–`34` | disjoint from CM/CD |
| CM | `70` (517), `72` (54) | 571/573 = 99.65% |
| CD | `71` (144), `73` (14) | 158/158 = 100% |

CM and CD's *dominant* segments barely overlap (2 CM students land in `71`, CD's home segment).
This is not documented anywhere we've found — purely empirical, discovered by checking real
data. It looks like Chula's own internal degree-level code baked into the ID at issuance, and CB
simply doesn't expose it as a labeled field.

**Validated against all 7,135 currently-matched students** (major_code + this student_id
heuristic, resolving to a program_group, compared against each student's actual local group):

- **99.97% agreement (7,133 / 7,135).**
- **Exactly 2 disagreements** — both `local=CM, guessed=CD`: student IDs `3971081121` (Primas
  Taechashong) and `3971235521` (Pheerakarn Sirivejabandhu), both `Program 0037` (CM, admitted
  1996-05-20, same cohort, both graduated). This is precisely the residual error rate the segment
  table above predicts — the heuristic isn't inventing new noise, it's hitting its known ceiling.
  **Manually confirmed (2026-07-05, via their thesis records): both are genuinely CM (Master of
  Engineering).** So the local data was correct and the heuristic was wrong for these two — real,
  confirmed evidence that this signal must never be trusted over an existing local record. This is
  exactly why the design flags disagreements for human review instead of ever auto-correcting.

**Refinement (2026-07-05): isolating segment `71` specifically (not the blended 99.97%) — and a
cheap fallback that fixes it.** The 99.97% aggregate blends fully-clean segments (`70`, `72`,
`73`: zero errors) with `71`, the one segment CM and CD actually share. Isolated: **146 local
students have `major_code=21100` and segment `71`; 144 are correctly CD, 2 are the CM exceptions
above — 98.63%, not 99.97%, for this segment specifically.**

But both exceptions were admitted in **2539 B.E. (1996)** — and CD's earliest local program
revision is **2541 B.E. (1998)**. They predate CD's existence as a program entirely. Adding one
fallback check — *if the group `segment=71` implies (CD) has no local `Program` with
`year_started_be <= admission_year_be`, fall back to the alternate candidate (CM)* — resolves
**146/146 = 100%** of the currently known `segment=71` cases, both exceptions included. This
isn't a special case for these two students; it's a natural consequence of Layer B's own
year-existence check (which the resolution algorithm needs anyway), applied as a general
fallback whenever Layer A's guess turns out to have no valid program for that year. **The
importer design now includes this fallback as part of Layer A**, not just the raw segment lookup.

**Decision: use this heuristic (with the fallback) for now.** Getting CB's maintainers to add `degree_code` (or an
equivalent signal) to the student export is the correct long-term fix, but realistically months
away. The student_id-segment heuristic is good enough to unblock the write-back importer today,
with two safeguards baked into the design (see the sync policy below): every group assignment
made via this heuristic (not a clean `major_code` case) is **flagged as an assumption**, never
silently trusted as fact, and this same resolution logic is reused to check *existing* matched
students for discrepancies — see the next section.

## 5. Existing-record discrepancy checking (not just new-student creation)

A separate but related question: when the importer runs against students who **already exist**
locally, do we ever detect and report a mismatch between their local program assignment and what
CB's signal implies — without touching the record?

**As designed so far, the importer does not check this at all** — its scope was "create the
~1,441 CB-only students," which by construction never reads or writes an existing student's
program. That satisfies "never silently overwrite," but not "loudly flag disagreement" — we
simply weren't looking.

The validation above changes that: running the *same* resolution logic against existing matched
students, purely as a comparison (never a write), found real, concrete disagreements — the 2
CM/CD cases above. **The importer design now includes a second, report-only pass**: for every
already-matched student, compute the CB-implied `program_group` (and, where unambiguous, the
specific `Program`) and compare against their actual local assignment. Any disagreement is
written to a dedicated report (e.g. `students_program_discrepancies.csv`) and surfaced
prominently in the rake task's console summary — but this pass **never updates the student
record**. `COMMIT=1` only ever affects the create-new-students pass; the discrepancy check has no
write path at all, by construction.

---

## 6. Design-review findings before the importer spec (2026-07-05)

A verification pass over this document's load-bearing claims, run against the actual import
population (the 1,441 CB-only students) rather than only the matched population:

**6a. The "lower program_code" twin default is contradicted by enrollment data.** Checking local
student counts inside each twin pair: the lower code holds the majority in only ~half the pairs.
Worst case `CP@2539`: `0570` has **0** students while its twin `0928` has **604** — a lower-code
default would assign new students to an empty program. Full counts: CD@2541 0458:83/0459:0 ·
CD@2558 2696:19/2697:1 · CD@2561 3482:16/3483:0/3484:15/3485:0 · CD@2566 4236:7/4237:1/4238:16/
4239:0 · CM@2558 2694:42/2695:7 · CM@2561 3336:48/3337:81 · CM@2566 4234:22/4235:74 · CP@2539
0570:0/0928:604 · SE@2545 0772:306/0773:19 · SE@2558 2628:50/2629:41 · SE@2561 3338:61/3339:102 ·
SE@2566 4240:44/4241:50 · SE@2569 5119:0/5120:0. **Revised default: majority-enrollment** (assign
to the twin with the most current local students; lower code only as a tiebreak when both are
empty). Still flagged in `remark` either way.

**6b. 7-digit (old-format) student IDs — a validated blind spot, small and bounded.** The
segment heuristic (§4) only applies to 10-digit IDs. 385 of the 1,441 CB-only students have
7-digit IDs. Mitigating evidence: all **442 matched** 7-digit-ID students are **CP (442/442)** —
no 7-digit ID has ever been observed on a graduate student. In the import population only **23
students** (7-digit + `major_code=21100`) depend on the resulting default-to-CP; each gets an
explicit `remark` flag.

**6c. Full resolution simulation on the real import population**: **1,432 / 1,441 (99.4%)
resolve** — CS 686, CP 229, SE 220, CM 215, CD 62, CEDT 20. Flags: 506 via the 21100 heuristic,
328 twin-ties. Unresolvable: exactly the 9 known `21103` students. The year-existence fallback
fires 0 times in this population (it remains as a safety net; §4 validates it on matched data).

**6d. Status-code families hold on the import population** (see the status crosswalk doc): every
CB-only status code maps into a known family; derived statuses for the 1,441 would be
**944 retired / 464 graduated / 33 active** — consistent with the 62.7%-pre-2010 cohort profile.
