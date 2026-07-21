# LINE LLM Tool Expansion — Round 2

Design for expanding the LINE chatbot's data-query tools to cover the
department's common questions, plus an eval harness that measures tool-selection
accuracy so this and every future tool addition is verified, not hoped for.

## Problem

The web app has rich info displays (entity pages, reports, charts), but the
LINE bot can only answer what its 7 registered tools cover. Sweeping the
question list against the current registry:

| Question | Status today |
|---|---|
| How many students in cohort X of program Y | Covered — `student_lookup` (`count_only` + filters) |
| How many students admitted in year X | Covered — same tool |
| Who taught a course, which section | Covered — `course_offering_lookup` |
| Grade distribution of a course | Covered — `grade_distribution` |
| Enrolled students of a course-term | **Gap** |
| One student's performance by term (transcript) | **Gap** — `student_lookup` returns only overall GPA |
| Semester summary / how many offerings | **Gap** — `course_offering_lookup` is per-course |
| Staff teaching load | **Gap** — `staff_lookup` lists teachings but doesn't sum load |
| Room schedule | **Gap** — planned in docs, never built |

Two standing concerns from `docs/llm-data-query.md` still apply:

- **Tool-count reliability**: open-weight models degrade at tool selection as
  the registry grows and descriptions overlap. Unquantified for the current
  model lineup (Qwen3.5-397B default, Gemma-4-31B fallback).
- **Maintenance**: every new report/page raises "should LINE answer this too?"
  with no process forcing the question.

## Decisions (from brainstorming, 2026-07-21)

1. **Audience**: staff/execs today, students possibly later. Thread the calling
   user through `ToolExecutor` now; keep permissive staff defaults; no
   per-tool authorization rules this round.
2. **"Enrolled in year X"** means *admitted* that year — already covered, no
   new tool.
3. **Course enrollment tool** returns counts + breakdown + a point membership
   check ("did student X take course Y in term Z?"). No bulk roster.
4. **Tool structure — approach B (consolidate)**: extend `staff_lookup` for
   workload instead of adding an overlapping twin; add four genuinely new
   tools; retire `echo`. Registry lands at 11 distinct, entity-focused tools.
5. **Eval harness first**: baseline the current registry, gate the new one on
   measured accuracy. Include a breaking-point sweep (accuracy vs. tool count
   with decoy tools) to learn the headroom curve per model.
6. **Models under test**: Qwen3.5-397B (DGX) and Gemma-4-31B (A100 box) are
   always live and form the standard matrix. GLM-5.2 / Kimi-K2.6 share the
   single DGX slot — evaluate opportunistically when swapped in, never block
   on them. **The shipping gate is Qwen3.5** (the default users hit); Gemma is
   the early-warning signal for smaller-model degradation.

## Phase 0 — Eval harness

### Case set

`test/llm_eval/cases.yml` — 30–50 natural-language questions, Thai and English
mixed, covering all existing tools and the four planned ones. Each case:

```yaml
- id: staff_teaching_th
  question: "อ.ณัฐสอนวิชาอะไรบ้าง"
  expect_tool: staff_lookup
  expect_params:
    query: "ณัฐ"
```

Scoring is **subset match**: `expect_tool` must equal the called tool's name;
every key in `expect_params` must appear in the call arguments with the
expected value (string compare after strip; integers compared numerically).
Extra parameters the model adds are ignored. Cases may also set
`expect_tool: none` for questions that should be answered without a tool call.

### Runner

`bin/rails llm:eval` (rake task, `lib/tasks/llm_eval.rake`):

- Sends each case through the existing LLM client path with the registered
  tool definitions, **selection-only**: capture the first tool call the model
  emits and score it. Tools are never executed — so candidate tool
  *definitions* can be evaluated before their handlers exist, and eval runs
  cannot touch data.
- Knobs (env vars, matching project convention): `MODEL=` (endpoint/model
  selection), `N=` repeats per case (default 3), `CASES=` id filter,
  `REGISTRY=` named registry variant (see sweep).
- Output: console table (per-case pass/fail, per-tool and overall selection
  accuracy, param accuracy) + CSV under `tmp/llm_eval/` for comparison across
  runs.

### Breaking-point sweep

`SWEEP=1` mode: run the same case set against progressively larger registries
— roughly current (8), candidate (11), padded (16), padded (24) — where padding
comes from a **decoy pool**: definition-only fake tools (`library_search`,
`payroll_lookup`, etc.) including a few deliberately near-overlapping ones.
Output: accuracy vs. registry size per model. Caveat recorded in the report:
the curve depends on decoy quality; it is indicative, not a universal law.

### Gate

Proceed to Phase 2 rollout only if, on Qwen3.5, the candidate registry scores
no more than 3 percentage points below baseline on the existing-tool cases
(no regression on shipped behavior) and at least 80% tool-selection accuracy
on the new-tool cases. If it fails, revise tool descriptions and re-run
before touching structure. Gemma numbers are recorded either way.

## Phase 1 — Infrastructure

- `Line::ToolExecutor.execute(tool_calls, user:)`; every handler signature
  becomes `call(arguments, user:)`. `LlmService` already holds `@user` — pass
  it through. No authorization logic this round; the parameter is the hook
  for student-scoped rules later.
- Retire `echo`: remove the tool file, its registration, and its tests.

## Phase 2 — Tools (approach B)

Shared-computation doctrine (unchanged from `docs/llm-data-query.md`): extract
a `GradeStats::*`-style service only where the web app already computes the
same thing; trivial aggregates stay inline in the tool. Web and LINE keep
separate presentation.

### `staff_lookup` — extend

Add to each teaching-assignment group it already returns: summed `load_ratio`
and section count per semester. Answers "how much does อ.X teach?" with no new
tool and no description twin.

### `student_grades` — new

One student's performance by term: the LINE-shaped version of the student show
page's course history.

- Params: `query` (student ID or name, required), `semester` (`"2568/1"`
  format, optional — omit for all terms), `limit` on terms (newest first).
- Output: per-term list of `{course_no, name, credits, grade}` + term GPA +
  cumulative GPAX, following Chula transcript terminology (GPA = semester,
  GPAX = cumulative).
- Ambiguous name match → disambiguation list, same convention as
  `staff_lookup`.
- Also answers "did X take Y in term Z?" indirectly (the model scans the
  term's course list).

### `course_enrollment` — new

- Params: `course_no` (required), `year` (required, B.E. or C.E. accepted),
  `semester` (optional), `student_query` (optional student ID/name).
- Output: total enrolled (count of Grade rows across curriculum revisions,
  matching `grade_distribution`'s revision-insensitive convention), breakdown
  by program group × admission cohort. With `student_query`: whether that
  student is enrolled, and their section if linked.
- No bulk roster output.

### `semester_overview` — new

- Params: `semester` (`"2568/1"`, optional — default latest).
- Output: offering count, section count, distinct course count, breakdown by
  program group. Subsumes "how many course offerings?".

### `room_schedule` — new

- Params: `room` (name query, required), `semester` (optional — default
  latest), `day` (optional weekday filter).
- Output: timetable entries `{day, time, course_no, name, section}` for the
  room, mirroring the room report's query (`SchedulesController#room`).
- Ambiguous room match → disambiguation list.

Registry after this phase: `student_lookup`, `student_grades`, `staff_lookup`,
`course_lookup`, `course_offering_lookup`, `course_enrollment`,
`grade_distribution`, `cohort_gpa`, `semester_overview`, `room_schedule`,
`search` — 11 tools, each with a distinct entity focus.

## Phase 3 — Process and docs

- **Backlog trigger** (`docs/backlog.md`): *Added or changed a report or an
  entity show page → check whether the LINE bot should answer the same
  question. If yes: add/extend a tool and add eval cases; if no: note why.*
  The eval harness makes each future addition verifiable by rerunning
  `llm:eval`.
- **Tool inventory** in `docs/line-integration.md`: rewrite the stale table to
  list all 11 tools (it currently omits 3 shipped ones); note `echo`'s
  retirement and the eval harness workflow.
- Record baseline + candidate + sweep results (per model) in the design doc's
  companion notes or the commit message of the rollout.

## Error handling

Same convention as existing tools: human-readable `{"error": "..."}` JSON that
the LLM relays conversationally. Unknown course/room/student → error with
valid-alternatives hint where cheap (mirroring `cohort_gpa`'s unknown-program
message).

## Testing

- Unit tests per tool (Minitest + fixtures): happy path, filters,
  disambiguation, error cases — written when the feature is finished, per
  project convention (ask before writing).
- The eval harness is the integration/regression net for model-facing
  behavior.

## Out of scope this round

- Per-tool authorization rules (student-scoped visibility) — enabled by the
  `user:` plumbing, deferred until students get linked.
- Personal "my schedule" / "my grades" queries — staff audience asks by name;
  revisit with student access.
- Commercial-model migration — a data-governance decision (student data would
  leave the university network), not an engineering one; tools must work on
  the local models.
- GLM-5.2 / Kimi-K2.6 eval gating — opportunistic numbers only, when swapped
  into the DGX slot.
