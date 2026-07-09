# Staff Teaching History Matrix — Design

**Date**: 2026-07-09
**Status**: Approved (pending spec review)

## Problem

Two existing views answer narrow slices of "what does this lecturer teach?":

1. `/staffs/:id?semester_id=N` — one semester at a time (dropdown), with section/load-ratio detail.
2. `/reports/staff_courses_by_year` — one B.E. year at a time, flat rows, admin-only, lookup by initials.

Neither shows a lecturer's whole teaching career at a glance. We want a matrix:
rows = year/semester (latest first), columns = courses (most-frequently-taught first),
cells = section numbers taught that term.

## Decision: placement

A new **"Teaching History" card on the staff show page**, below the existing
per-semester Teaching card. Both existing views stay unchanged:

- The staff page already has staff identity (no params to type) and is visible to
  all logged-in users, not just admins.
- The per-semester card keeps detail the matrix lacks (load ratio, course names inline).
- The `staff_courses_by_year` report keeps its admin lookup-by-initials + CSV role.

## Data — `Staff#teaching_history(max_years: 20)`

Model method (unit-testable), one query, pivoted in Ruby (a full career is a few
hundred `Teaching` rows at most):

```ruby
Teaching.where(staff:).joins(section: { course_offering: [:course, :semester] })
        .includes(section: { course_offering: [:course, :semester] })
```

Returns a small value object (Struct) with:

- **`semesters`** — distinct `Semester` records the staff actually taught in (no
  empty gap rows), ordered `year_be desc, semester_number desc`. Capped to
  semesters with `year_be >= newest_taught_year_be - (max_years - 1)` — anchored
  at the staff's most recent teaching, not today's year, so a retired lecturer
  still shows their last 20 active years. `max_years: nil` disables the cap.
- **`courses`** — one entry per distinct `course_no`, merging curriculum revisions
  (same convention as `Reports::StaffCoursesByYear` and the grade reports). Each
  entry: `course_no`, display `name` (from the latest revision taught), and the
  latest-revision `Course` record (for linking). Ordered by number of distinct
  semesters taught descending, tie-broken by `course_no` ascending. Course
  frequency is computed over the **capped window** (columns match visible rows).
- **`cells`** — hash keyed `[semester_id, course_no]` → uniq sorted section
  numbers joined with `", "` (e.g. `"1, 33"`). Absent key = not taught that term.
- **`capped`** — boolean: true when older teaching semesters exist beyond the window.

Returns `nil` when the staff has no teachings.

## Controller

One addition to `StaffsController#show`:

```ruby
@teaching_history = @staff.teaching_history(max_years: params[:history] == "all" ? nil : 20)
```

Existing `@teaching_semesters` / `@teachings` per-semester code is untouched.

## View

New card in `app/views/staffs/show.html.haml`, rendered only when
`@teaching_history` is present, below the existing Teaching card:

- Card title "Teaching History" following the existing card-title pattern
  (Material Symbols icon + `%h5.card-title`).
- Table inside `.table-responsive` (existing table-in-card pattern) — a wide
  matrix must scroll inside the card, never the page.
- First column: term as `year_be/semester_number` (`Semester#display_name`,
  e.g. `2568/2`), one row per semester, latest first. Rendered as row-header `%th`.
- One column per course. **Header is the `course_no` only, rotated 90°**, reading
  bottom-to-top, linked to the course show page, with the course name in a
  `title` tooltip. Rotation keeps ~30 columns within card width; course numbers
  are 7 chars so the header band stays short (~5–6rem).
- Cells: section numbers (`"1, 33"`) or blank.
- When `capped` is true: muted footer line
  "Showing last 20 years — [Show all]" where Show all links to
  `staff_path(@staff, history: "all")`.

### Rotated header SCSS

New component class in `application.scss` (e.g. `.th-rotated`):
`writing-mode: vertical-rl` + `transform: rotate(180deg)` so text reads
bottom-to-top, bottom-aligned so labels sit on the column baseline. Inherits the
global quiet-label `thead th` treatment (size/color); the link inside inherits
header color with normal hover affordance.

## Not changing

- Per-semester Teaching card on the staff page.
- `Reports::StaffCoursesByYear` report.

## Error handling

- No teachings → method returns `nil`, card not rendered. No other failure modes:
  read-only pivot over already-validated associations.
- `?history=all` with nothing beyond the cap is harmless (same rows, no footer).

## Testing

Per project convention, discussed after implementation. Expected coverage:

- **Model tests** for the pivot: row ordering (year desc, semester desc), column
  ordering (frequency desc, course_no tiebreak), revision merging under one
  `course_no`, cell section-number formatting, 20-year cap + `capped` flag
  anchored at most recent teaching, `nil` when no teachings.
- **System test** (optional): card renders on staff page with matrix content;
  "Show all" link appears only when capped.
