# Sticky Term Context — Design

Date: 2026-07-20
Status: Approved
Part 3 of 3 in the report-findability decomposition
(Part 1: `2026-07-19-report-hub-consolidation-design.md`; Part 2: `2026-07-20-home-launchpad-design.md`)

## Problem

Almost every report asks "which term?" — and the app has no memory of the
answer. Open the room schedule for 2568/1, then staff workload, then the grade
distribution, then the teaching matrix, and you re-enter the term four times.
Part 1 gathered the reports into one hub and Part 2 gave the app a real home
page; both improved *finding* a report. This is the friction that remains
*inside* the reports once found.

The fix: set your working term **once**, and every relevant report form arrives
**pre-filled** with it. It is only a starting point — you can change the term on
any single report, and doing so disturbs neither your sticky setting nor any
other report.

## The domain unit

The thing worth remembering is not "a term" but an **academic year plus which
semester within it**. A Chulalongkorn academic year (AY) has two main semesters
(1st: Aug–early Dec, 2nd: Jan–early May) and a short summer semester. The AY
crosses the Gregorian new year, which is exactly why the app already stores
`Semester#year_be` (the AY) rather than a calendar year.

So the canonical context is a pair: **(academic_year_be, semester)**, where
`semester` is one of `1`, `2`, `3` (summer), or **nil = "whole year."**

## Decisions (and the alternatives rejected)

1. **Defaults only.** The context pre-fills forms. It never reshapes what a
   report shows, and changing a report's term never writes back to the context.
   (Rejected: a global filter that scopes every page; and "remember my
   overrides" — both make a control act at a distance.)
2. **Term only, not program.** Term is consumed by nine reports; program by two,
   and program has three incompatible representations (`program_group`,
   `program_code`, course-number `prefix`). Program stickiness is a possible
   future Part, not this one.
3. **Default = the latest semester that exists** (`Semester.ordered.first`).
   This is already the de-facto default in `Reports::Base#semester_scope` and
   the teaching matrix, so the default needs no new logic and always corresponds
   to a real row. (Rejected: deriving the "current" term from today's date —
   it drags in the university calendar to answer a question the user can
   override in one click. Known risk accepted: *latest ≠ current*; a scrape of
   next term's schedule advances the default. Survivable, because it is only a
   default and is exactly today's behavior.)
4. **Stored in the session.** Lasts while logged in; resets to the default on
   next login. (Rejected: a signed cookie and a per-user column — premature
   while there is one login, and the session store swaps for a column later
   without changing any consumer.)
5. **Selector lives in a context bar on report pages**, not the sidebar. It
   appears where term matters and leaves the sidebar and non-report pages
   untouched. (Rejected: a sidebar-global picker — tidier to wire but visible on
   pages where term is meaningless.)
6. **Range reports ignore the context.** Staff Workload and Class Grade
   Distribution show a *span* of years; seeding one end of a multi-year chart
   from a single sticky year is the action-at-a-distance decision 1 forbids.
   They keep their own "last few years" defaults.

## The cohort trap (the one real correctness risk)

Three reports — **Cohort GPA, Group Credit Shortfall, Thesis Credits** — take an
`admission_year`. That is a **cohort identity** ("the AY 2568 entering class"),
not a viewing term. It is deliberately robust to the calendar: students admitted
in the 2nd semester carry the same `admission_year_be` as the 1st-semester
intake, and the whole "68 cohort" is understood as one class regardless — as
encoded in the student ID's leading digits. Feeding these reports the sticky
year would silently show wrong data.

The danger is that `admission_year` and a viewing `year` are **the same param
type** (`:academic_year`) in the code. The type cannot distinguish them.
Therefore opt-in is **per field and explicit** (see below): a viewing-year field
opts in; an admission-year field is simply never marked, and inherits nothing.

## Architecture

One source of truth, read through two paths because the reports were built two
ways.

### `TermContext` (the single source of truth)

A plain Ruby object (`app/services/term_context.rb`), constructed from the
session and the `Semester` table.

```ruby
TermContext.from_session(session)   # => TermContext
```

State: `academic_year_be` (Integer or nil) and `semester_number` (1/2/3 or nil).

Resolution:
- If the session holds a `(year_be, semester)` pair, use it.
- Otherwise fall back to `Semester.ordered.first` → its `year_be` and
  `semester_number`. If no semester exists at all, both are nil.
- A stored pair whose `year_be` is no longer present in the data falls back to
  the default rather than erroring.

Projections (what the two read-paths consume):
- `academic_year_be` → the AY, for year-shaped fields
- `semester_number` → 1/2/3 or nil, for term-shaped fields
- `semester_record` → `Semester.find_by(year_be:, semester_number:)` or **nil**
  (may not exist; callers treat nil as "unspecified," exactly as a blank param)

The session stores the **pair, not a `Semester#id`** — so year-level reports work
in a year that has no matching semester row, and a deleted row cannot dangle.

Session shape: `session[:term_context] = { "year_be" => Integer, "semester" => Integer | nil }`.

`ApplicationController` exposes `current_term_context` (memoized, also a
`helper_method`) so controllers and views share one instance per request.

### The selector: a context bar

A partial `app/views/shared/_term_context_bar.html.haml`, rendered at the top of
report pages (the reports hub, each registry report's show page, and each
schedule report page). Two dropdowns:

- **Academic year** — `Semester.distinct.pluck(:year_be)` descending.
- **Semester** — `Whole year` (blank) · `1` · `2` · `Summer`.

Changing either submits to `TermContextsController#update`, which writes the
session and `redirect_back(fallback_location: root_path)` so the current page
re-renders with the new defaults. Submit-on-change via a small Stimulus
controller; a plain submit button is an acceptable fallback. The bar always
shows the currently resolved context (including the default), so the user can
see what they are "working in" even before setting anything.

When no semesters exist, the bar renders a quiet "No terms yet" state instead of
empty dropdowns.

### Read-path 1 — registry reports (the `Reports::Base` DSL)

These render through `ReportsController#show` and
`app/views/reports/_form.html.haml`, which builds each field from
`@report.params_spec` by `:type`.

Add an explicit opt-in to the `param` DSL:

```ruby
param :year, :academic_year, required: true, context: :year
param :term, :term,          context: :semester   # opt-in is independent of required:
```

`context:` names which projection fills the field when the submitted value is
blank: `:year` → `academic_year_be`, `:semester` → `semester_number`,
`:semester_record` → `semester_record&.id`. A param with no `context:` is never
filled. `context:` is orthogonal to `required:` — Failing Students' `term` is
optional yet opts in (when the sticky semester is "whole year" the projection is
nil, so the field simply stays blank).

`_form.html.haml` pre-fills each field's selected value with
`params[p[:name]].presence || context_default_for(p)`, where a `ReportsHelper`
method returns the projected value for an opted-in param and nil otherwise. This
sets the form's initial value only; the report still runs on submit (`run=1`),
so this is pre-fill, not auto-run. An explicit param always wins.

Registry reports that opt in:

| Report | Field → projection |
|---|---|
| Semester Grade Distribution | `year` → year, `term` → semester |
| Failing Students | `year` → year, `term` → semester |
| Staff courses by year | `year` (`:teaching_year`) → year |

Registry reports that must **not** opt in: Cohort GPA (`admission_year`), Group
Credit Shortfall (`admission_year`), Thesis Credits (`admission_year`), Data
Coverage (no term field).

### Read-path 2 — schedule reports (`SchedulesController`)

The five schedule calendars and the teaching matrix are hand-rolled controller
actions reading `params[...]` directly. Each falls back to the context when its
own param is blank:

| Action | Param → fallback |
|---|---|
| room, staff, student, curriculum, conflicts | `semester_id` → `current_term_context.semester_record&.id` |
| teaching_matrix | `year` → `academic_year_be`; `semester_number` → `semester_number` (optional) |

The fallback sets the pre-selected value in each hand-rolled form's semester
dropdown. As today, these pages only render results once their *other* required
input (room, staff, student, course) is also chosen — so the context pre-selects
the term and the user still picks the entity. Explicit params always win, so
every existing deep-link test continues to pass untouched.

### Reports that consume nothing

Staff Workload, Class Grade Distribution (ranges); Cohort GPA, Group Credit
Shortfall, Thesis Credits (cohort); Data Coverage (admin). Nine reports consume
the context; five abstain.

## Edge cases

- **No semesters at all**: context is empty (both fields nil), the bar shows "No
  terms yet," and every report behaves as it does today with blank inputs.
- **Sticky pair has no matching row** (e.g. Summer of a year with no summer):
  `semester_record` is nil, so single-semester reports prompt as they do today;
  year-level reports still work, since they read only the year.
- **Stale session value** (a `year_be` since removed): resolves to the default.
- **Explicit choice wins**: a term chosen on a report, or named in a deep link,
  overrides the context. The context only fills a gap.

## Testing

- **`TermContext` unit** (`test/services/term_context_test.rb`): default resolves
  to the latest semester; a session value overrides it; a stale/missing value
  degrades to the default; projections to `academic_year_be`, `semester_number`,
  and `semester_record` are correct, including `semester_record` nil when no row
  matches.
- **Wiring** (controller/integration): an opted-in field pre-fills from context
  when blank; an explicit value overrides it; and — the regression guard that
  matters most — a **cohort report's `admission_year` is provably not filled**
  from the context. A schedule action falls back to the context semester when
  `semester_id` is blank and honors an explicit `semester_id` when given.
- **`TermContextsController`**: `update` writes the session pair and redirects
  back; an out-of-range submission is ignored rather than stored.
- **System** (`test/system/term_context_test.rb`): set a term in the bar, open a
  consuming report and see it pre-filled, change it there and confirm the sticky
  setting is unchanged elsewhere; open a range report and a cohort report and
  confirm both ignore the context.

## Files

**New:**
- `app/services/term_context.rb`
- `app/controllers/term_contexts_controller.rb` + route (`resource :term_context, only: :update`)
- `app/views/shared/_term_context_bar.html.haml`
- a Stimulus controller for submit-on-change (or reuse an existing one)
- the three test files above

**Modified:**
- `app/services/reports/base.rb` — `param` accepts `context:`; `params_spec` carries it
- `app/views/reports/_form.html.haml` — pre-fill from `context_default_for`
- `app/helpers/reports_helper.rb` — `context_default_for(param)`
- `app/services/reports/semester_grade_distribution.rb`, `failing_students.rb`,
  `staff_courses_by_year.rb` — add `context:` to the viewing-term params
- `app/controllers/application_controller.rb` — `current_term_context` + `helper_method`
- `app/controllers/schedules_controller.rb` — context fallback in the six actions
- schedule views + the reports hub/show views — render the context bar

**Deliberately untouched:** the sidebar; the three cohort reports; the two range
reports; `Reports::Catalog`; every report's `#run` logic (this feature changes
defaults, never computation).

## Non-goals

- No program stickiness (decision 2).
- No auto-run: forms arrive pre-filled, the user still runs them.
- No "current term" calendar (decision 3).
- No write-back from reports to the context (decision 1).

## Open questions

None.
