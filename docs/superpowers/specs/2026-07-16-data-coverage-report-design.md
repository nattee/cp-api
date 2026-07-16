# Data Coverage Report — Design

**Date**: 2026-07-16
**Status**: Approved (brainstorm with dae)

## Problem

Three ingestion paths must each run at least once per semester (grades, schedule,
new-student import), but nothing tells us when a term was missed. `data_imports`
rows don't record which year/semester a file covered, and term data also arrives
via the CuGetReg scraper and ChulaBooster sync — so auditing *import runs* can't
answer the real question. The real question is **data presence**: for each term,
do we have the grades, schedule, and students we expect?

## Goal

One admin report — a per-term coverage matrix — where a missed dataset is
visually obvious (red/yellow cells), with a toggle to count only curriculum
courses, plus a summary diagnostic for un-imported curriculum revisions.

## Non-goals

- Auditing DataImport/Scrape execution history (the existing index pages do that).
- Date-aware expectations ("grades due after term end") — revisit only if the
  red current-term cell becomes annoying.
- A LINE bot tool. This is web/admin-only; no shared `GradeStats::`-style
  extraction needed.

## Design

### Report class & placement

- `app/services/reports/data_coverage.rb` — `Reports::DataCoverage < Reports::Base`,
  key `data_coverage`, title "Which terms are missing data", `programs :all`.
- Queries inline in `#run` (the `FailingStudents` shape — no shared service).
- New registry section: `admin: "Data"` appended to `Reports::Registry::SECTIONS`;
  one line added to `REPORTS`.

### Rows (terms)

Union of:
- `Semester` records (`year_be`, `semester_number`), and
- distinct `(year_ce + 543, semester)` pairs from `grades`.

Ordered newest first. Summer terms (semester 3) appear naturally where data
exists. No year-range parameter — the union bounds the list.

### Columns

| Column | Source | Notes |
|---|---|---|
| Term | — | `"#{year_be}/#{semester}"` |
| New students | `Student.group(:admission_year_be)` count | Semester-1 rows only; "—" on rows for semesters 2/3 |
| Grades | `Grade` count for the term | |
| Ungraded | `Grade` count for the term with `grade: nil` | "enrollments in, grades not posted yet" |
| Offerings | `CourseOffering` count via the term's `Semester` | 0 when the term has no Semester record — the era rule decides "—" vs red |
| Sections | `Section` count via offerings | " |
| Time slots | `TimeSlot` count via sections | " |

Separate numeric columns (no composite strings) so DataTables sorting and CSV
stay clean. Pre-era / not-applicable cells carry the literal string "—" (it
flows into CSV too — acceptable).

### The era rule (avoids a wall of false red)

Schedule data only exists for recent terms; old terms have grades but never had
`Semester`/offering rows. Per dataset column, flagging applies only from that
column's **earliest term with a non-zero count** onward. Before its era the cell
renders "—" (muted, no flag class). Data-driven; no configuration. Each of the
three schedule columns computes its own era (uniform and simple, even if they
coincide in practice). New students' era comes from the earliest
`admission_year_be`.

### Flagging (within era)

- **Red** (`report-cell-missing`): count is 0.
- **Yellow** (`report-cell-low`): count < 50% of the **median of non-zero counts
  for the same semester-number across other years** (summers compare with
  summers; zeros excluded so past missed terms don't drag the baseline down;
  the row's own value is excluded).
- Current/future terms are not special-cased: a scraped 2569/2 schedule row
  shows red zero grades until grades arrive. Accepted noise (approved).

### Filter: "Program courses only"

One checkbox param (default off). When on, the five course-based counts
(Grades, Ungraded, Offerings, Sections, Time slots) are restricted to courses
that have **any** `program_courses` row — i.e. part of some curriculum —
excluding gen-ed / other-faculty courses. New students are unaffected (all
students belong to our programs).

Requires a new `:boolean` param type: one `when :boolean` branch in
`app/views/reports/_form.html.haml` rendering a checkbox (`check_box_tag`,
value `"1"`).

### Courses dataset → summary diagnostic, not a column

Course revisions aren't term data. Instead, the result `summary` appends a
warning listing `Program` revisions with **zero** `program_courses` rows —
e.g. "⚠ CEDT 2571 (4784): no courses linked" — catching "new curriculum
arrived, its courses were never imported". Silent when every program has
linked courses.

### Framework extension: per-cell CSS classes

- Column spec gains optional `class_key:` (e.g.
  `{ key: :grades, label: "Grades", class_key: :grades_class }`).
- A row may carry that key (`grades_class: "report-cell-missing"`); the value is
  applied as the `<td>` class in `_result_table.html.haml`.
- `Exporters::ReportExporter` reads only declared column keys, so CSV is
  unaffected — verified, no exporter change needed.
- Two new classes in `application.scss` near the badge styles: frosted red and
  yellow tints (`report-cell-missing`, `report-cell-low`), commented per the
  styling conventions.
- Generic: any future report can flag cells the same way.

## Backlog compliance (docs/backlog.md — both triggers fire)

- **Item 1 (entity → report cross-links)**: `/data_sources` gets a link to this
  report ("check per-term coverage"); extend the item's seed list with it.
- **Item 2 (report ↔ entity overlap)**: no single-entity anchor — set/aggregate
  report, "keep regardless" category; add it to the status list.

## Testing (later, per usual flow)

The fiddly logic is era detection + median flagging. Report-class unit tests
with fixture terms covering:

- pre-era cells render "—" with no flag class
- zero within era → red class
- low vs same-semester median → yellow class (and: median excludes zeros and
  the row's own value; summer compares only with summers)
- "Program courses only" toggle changes counts
- semester-1-only behaviour of New students
- curriculum diagnostic appears only when a program has no linked courses

System test: run the report from `/reports`, assert the table renders with
highlighted cells and the checkbox round-trips.
