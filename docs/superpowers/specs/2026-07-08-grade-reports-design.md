# Grade Distribution & Cohort GPA Reports — Design

**Date:** 2026-07-08
**Status:** Approved

## Motivation

Staff need to answer two recurring questions that the app currently cannot:

1. **"How did each course do in a given semester?"** — e.g. "What is the grade
   distribution of 2110327 in semester 2/2025?" Answer: A:20, B+:13, B:19, …
   plus the course GPA. Eventually as a table: one row per course, one column
   per grade, for a whole semester.
2. **"How did this class year do each semester?"** — per-term GPA of each
   student in a cohort, aggregated (AVG, SD, MIN, MAX, ±2SD) per semester.

Both reports must be available on the web UI and through the LINE bot.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Cohort GPA semantics | **Both** term GPA (GPS) and cumulative GPA (GPAX) per semester |
| Non-letter grades (S, U, I, W, V, M, P, R, X) | Show **all grades present** as columns, ordered by `Grade::GRADES`; they count in distributions but never in GPA |
| Cohort definition | **Program group + admission year (B.E.)** |
| Course table scope | **Program-filtered only** — program group is a required param |
| LINE scope | Single-course distribution + cohort GPA stats. The full multi-course table is **web-only** |
| Charts | **Yes, in v1** (see Web Reports) |
| Architecture | **Shared services** (`GradeStats::*`) + thin `Reports::*` classes (web) + thin `Line::Tools::*` (LINE) |

## Core semantics

- **Courses aggregate by `course_no`, never by revision.** All enrollments of
  all revisions of a course in a term count together — one distribution, one
  GPA, one table row. This matches existing convention (revision-insensitive
  grade identity in the ChulaBooster sync; `Reports::FailingStudents`).
- **GPA counts weighted grades only** (`grade_weight` not nil, i.e. A–F).
  S/U/W/etc. appear in distribution counts but never affect GPA or N-for-GPA.
- **GPS** (term GPA) = Σ(grade_weight × course credits) / Σ(credits) over one
  student's weighted grades in one term. **GPAX** = the same, cumulative over
  all terms up to and including that term (ordered by `year_ce`, `semester`).
- **SD is sample SD** (n−1 denominator).
- **GPA statistics are rounded to 2 decimals inside the services**, so web and
  LINE always show identical numbers.
- **Year conventions:** web forms take B.E. and convert (−543) to `Grade#year_ce`,
  like `Reports::FailingStudents`. LINE tools accept either era; values < 2400
  are treated as C.E. (same rule as the importers).

## Section 1: Shared stats services — `app/services/grade_stats/`

Three plain query objects. Each is a class-method `call` returning a hash.
No web or LINE assumptions — both surfaces read the same numbers.

### `GradeStats::CourseDistribution.call(course_no:, year_ce:, semester:)`

Query: `Grade.joins(:course).where(courses: { course_no: }, year_ce:, semester:)`.

Returns:

```ruby
{
  course_no: "2110327",
  year_ce: 2025, semester: 2,
  total: 61,                                  # all grade rows, incl. S/U/W
  counts: { "A" => 20, "B+" => 13, ... },     # Grade::GRADES order, present only
  gpa: { n: 58, mean: 3.12, sd: 0.61 }        # weighted grades only
}
```

`semester: nil` is allowed: returns one such hash per term of the year that
has grades (used by the LINE tool when the user doesn't name a term).

### `GradeStats::SemesterCourseTable.call(program_group:, year_ce:, semester:)`

Course set = the program group's curriculum:
`Course.joins(program_courses: { program: :program_group })` filtered by group,
deduped by `course_no`. Grade counts and GPA stats come from GROUP BY queries
on `courses.course_no` (so revisions merge). Course names come from the latest
revision.

Returns:

```ruby
{
  grade_columns: ["A", "B+", "B", ..., "W"],  # union of grades present, ordered
  rows: [
    { course_no:, name:, total:, counts: {...}, gpa: { n:, mean:, sd: } },
    ...                                        # ordered by course_no
  ]
}
```

### `GradeStats::CohortGpa.call(program_group:, admission_year_be:)`

Cohort = `Student.joins(program: :program_group)` filtered by group code and
`admission_year_be`. Plucks all weighted grades of the cohort once
(`student_id, year_ce, semester, grade_weight, credits`) and computes GPS and
GPAX per student per term in Ruby — a cohort is a few hundred students, and
cumulative GPA per term is trivial in Ruby but painful in MySQL.

Returns one entry per (year_ce, semester) with grades, chronological:

```ruby
{
  terms: [
    { year_ce: 2022, semester: 1,
      gps:  { n:, avg:, sd:, min:, max:, minus2sd:, plus2sd: },
      gpax: { n:, avg:, sd:, min:, max:, minus2sd:, plus2sd: } },
    ...
  ]
}
```

`n` counts students with ≥1 weighted grade in scope for that statistic; a
student with only S/U grades in a term does not appear in that term's GPS.
`minus2sd`/`plus2sd` are `avg ∓ 2×sd`, reported raw (not clamped to 0–4).

## Section 2: Web reports

Two new classes in `app/services/reports/`, one line each in
`Reports::Registry::REPORTS`. Param form, result table, and CSV export come
free from the existing framework. Admin-only via `ReportsController`.

### `Reports::SemesterGradeDistribution` — section `:courses`

- Params: `program_group` (required), `year` (`:academic_year`, B.E., required),
  `term` (`:term`, required).
- Columns: Course No | Name | N | one column per grade in `grade_columns` | GPA | SD.
- Chart: existing `horizontal-stacked-bar` type — one bar per course,
  segments per grade.

### `Reports::CohortGpa` — section `:students`

- Params: `program_group` (required), `admission_year` (`:academic_year`, B.E.,
  required).
- Columns: Term | N | GPS avg, SD, min, max, −2SD, +2SD | GPAX avg, SD, min,
  max, −2SD, +2SD. Wide, but that is what the CSV needs; the chart carries
  readability.
- Chart: extend the existing `gpa-trend` line type to accept a shaded band —
  GPS avg line with ±2SD fill band, GPAX avg as a second dashed line.

### Framework extensions

- `_form.html.haml` gains a `:program_group` param type — one `when` branch
  rendering a select of `ProgramGroup.order(:code)`.
- `Reports::Result` gains an optional `chart` field (`{ type:, data: }`);
  `reports/show.html.haml` renders a canvas wired to `chart_controller` when a
  result carries one. Reports without charts are unaffected.

## Section 3: LINE tools

Two new classes in `app/services/line/tools/`, registered in
`config/initializers/line_tools.rb`, same pattern as the existing six tools.
Tools return compact JSON; the LLM phrases the reply.

### `Line::Tools::GradeDistributionTool` (`grade_distribution`)

- Params: `course_no` (required), `year` (required, B.E. or C.E. — < 2400 is
  C.E.), `semester` (optional 1/2/3).
- With `semester`: one `CourseDistribution` result, plus the course name.
- Without: one distribution per term of that year (saves the LLM a retry
  round-trip when the user doesn't name a term).

### `Line::Tools::CohortGpaTool` (`cohort_gpa`)

- Params: `program_code` (CP/CEDT/CM/CS/SE/CD, required), `admission_year`
  (required, same era rule).
- Returns the `CohortGpa` terms array as-is. The LLM summarizes a trend or
  picks out a single term as asked.

The full multi-course table is intentionally not exposed on LINE.

## Section 4: Testing

Written after the feature works (project preference). Coverage plan:

- **Service tests** (the math): counts ordered by `Grade::GRADES`;
  cross-revision rows of one `course_no` combined; S/U/W in counts but not GPA;
  program-group filtering of the course table; grade-column union; GPS vs GPAX
  hand-checked against a small fixture cohort; sample SD; chronological term
  order; only-S/U-in-a-term student excluded from that term's GPS `n`.
- **Report tests**: expected columns/summary; present in Registry.
- **LINE tool tests**: well-formed JSON; era rule both directions
  (2568 → `year_ce` 2025; 2025 → 2025).
- **System test** (happy path per report): run from the web form, table renders
  with grade columns, chart canvas present.
- **Fixtures**: a small deliberate grade set with a known distribution and two
  students with known GPAs.

## Out of scope

- Multi-course table on LINE.
- Precomputed/materialized summary tables (plain GROUP BYs are instant at this
  data volume).
- Charts beyond the two specified.
- Non-admin access to reports.
