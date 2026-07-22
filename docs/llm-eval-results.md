# LLM Tool-Selection Eval Results

Selection-only accuracy from `bin/rails llm:eval` (see docs/line-integration.md
for the harness). Gate for registry changes: on qwen, existing-group tool
accuracy within 3 points of baseline AND new-group tool accuracy ≥ 80%.

## 2026-07-21 — round-2 gate (baseline 7 tools vs candidate 11), N=3

| model | registry | tools | existing tool% | existing t+p% | new tool% | new t+p% | none% |
|---|---|---|---|---|---|---|---|
| qwen  | current   | 7  | 100.0 | 100.0 | n/a¹ | n/a¹ | 100.0 |
| qwen  | candidate | 11 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| gemma | current   | 7  | 0.0²  | 0.0²  | n/a¹ | n/a¹ | 100.0 |
| gemma | candidate | 11 | 0.0²  | 0.0²  | 0.0² | 0.0² | 100.0 |

¹ New-group cases under the current registry score 7.1% — exactly the one case
(`gpa_of_student_ambiguous`) whose accept-list includes an existing tool.
Expected; the new tools aren't in that registry.

² **Gemma's zeros are a plumbing failure, not a selection failure.** Probing
the endpoint directly shows gemma picks the right tool with the right param —
but emits it as plain content in the form `call:student_lookup{query:...}`
(non-JSON args). The A100 vLLM deployment has no tool-call parser enabled for
gemma (`tool_calls` comes back empty) and `Line::ToolCallParser` doesn't know
that format, so every attempt scores "none". **This is a live production gap
today**: LINE users who `/model` to gemma get no data-query capability at all.
Fix paths (backlog, out of round-2 scope): enable a vLLM tool parser for gemma
on the A100 box, and/or extend ToolCallParser to parse `call:name{...}`.

No transport errors in any run (all 1,176 requests returned 200).

## Breaking-point sweep (N=2)

qwen, tool-selection accuracy per registry size:

| tools | existing tool% | new tool% |
|---|---|---|
| 7 (current)        | 100.0 | 7.1¹ |
| 11 (candidate)     | 100.0 | 100.0 |
| 16 (+5 decoys)     | 100.0 | 100.0 |
| 24 (+13 decoys, incl. 4 near-overlap) | 100.0 | 100.0 |

Gemma: flat 0% at every size (see ² — parser plumbing, so registry size is
unmeasurable for it until that's fixed).

**Reading:** qwen shows no degradation whatsoever through 24 tools, including
deliberately near-overlapping decoys (meeting_room_booking vs room_schedule,
admission_stats vs student_lookup counts, etc.). The old "8–10 tools degrades
selection" doctrine from docs/llm-data-query.md does not apply to the current
default model; registry growth headroom is ample. Caveat: the curve depends on
decoy quality (test/llm_eval/decoy_tools.yml); it is indicative, not a
universal law — and it says nothing about smaller models (see gemma).

## Gate decision

- Qwen existing regression: 100.0 → 100.0 = **0.0 points** (limit 3) → PASS
- Qwen new-tool accuracy: **100.0%** (floor 80%) → PASS
- Decision: **PASS — rollout completed 2026-07-22** (whole-branch review confirmed; tools registered and verified live).

Raw logs and per-attempt CSVs: `tmp/llm_eval/` (`run-{qwen,gemma}-{current,candidate,sweep}.log`, `2026...csv`).

## 2026-07-22 — round-3 gate (13 tools: + cohort_ranking, missing_enrollments), N=3

qwen: existing 100/100, new 100/100, none 100/100 (162/162 attempts — includes
the cohort-label definitional cases, the array-valued course_nos param, and
the ranking_vs_stats_guard confirming "GPAX เฉลี่ย" still routes to cohort_gpa).
Same-day earlier gates: 46-case run after the emoji FORMATTING prompt
(138/138), 48-case run after the CP51 description fix (144/144).
Post-unification rerun (shared description constants, round-3 tools
strengthened with the anti-2551 guard): 162/162.
