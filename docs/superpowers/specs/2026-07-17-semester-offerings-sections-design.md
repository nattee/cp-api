# Semester Offerings Table: Per-Section Detail, Course Filter, CSV Export

**Date:** 2026-07-17
**Status:** Approved design, pending implementation

## Problem

The Course Offerings table on `semesters/show` answers "which courses run this
term" but not the questions people actually bring to it: who teaches each
section, when and where it meets, and how full it is. That data exists
(Teaching, TimeSlot, Section enrollment columns) but is only visible by
clicking into each offering. There is also no way to narrow the list to
department courses (`2110xxx`) or to pull the term's section list into a
spreadsheet — the existing "Export CSV" button emits the schedule *import
round-trip* format (one row per time slot, no enrollment/status), which is not
a human-facing listing.

## Decision summary

1. **Enrich the existing table** on `semesters/show` — no new page, no new
   report. One row per offering; the "Sections" count column becomes a detail
   column with one line per section.
2. **Course scope toggle** — `course_scope=dept|all`, **default `dept`**
   (`course_no LIKE '2110%'`), same param semantics as the Teaching Matrix
   report (`schedules_controller.rb#teaching_matrix`).
3. **New CSV export, one row per section**, honoring the current scope.

## 1. Table change (`app/views/semesters/show.html.haml`)

Columns: `Course No | Course Name | Sections | Status | Actions` (DataTable,
unchanged controller-side wiring). The Sections cell renders one line
(`%div`) per section, ordered by `section_number`:

```
Sec 1 · NNN, PKY · Mon/Wed 09:00-10:30 ENG4-303 · 45/50
Sec 2 · SPL · Tue 13:00-14:30 ENG3-401; Fri 09:00-11:00 TBA · 30/50
```

Per-line format, parts joined by a muted `·` separator (values stay primary —
visual-hierarchy convention):

- **`Sec N`** — section number.
- **Teachers** — links to staff pages, text `initials.presence ||
  display_name_th` (same rule as the courses/show Teachers column). Omitted
  when the section has no teachings.
- **Schedule** — time slots grouped by identical `(start_time, end_time,
  room_id)`; each group renders as `day_abbr` values joined with `/` +
  `time_range` + room `display_name` (or `TBA` when room is nil). Groups
  joined with `;`. Omitted when the section has no time slots. Groups are
  ordered by first day/start time.
- **Enrollment** — `current/max`; a nil side renders as `?` (e.g. `45/?`);
  omitted entirely when both are nil.
- Offering with zero sections → muted *No sections* text in the cell.

DataTable search now matches teacher initials, room names, and section
numbers. Section-level sorting is explicitly not a goal (the column is
unsortable in any meaningful way; default sort stays on Course No).

## 2. Course scope toggle

- Param: `course_scope`, values `dept` (default) / `all`, parsed exactly like
  teaching_matrix: `params[:course_scope] == "all" ? "all" : "dept"`.
- `dept` filters `joins(:course).where("courses.course_no LIKE ?", "2110%")`.
- UI: a small two-button toggle (btn-group of `btn-outline-*` links, active
  state on the current scope) in the card title row, linking to
  `semester_path(@semester, course_scope: ...)`.
- The card-title offering count reflects the filtered set.
- Both export buttons (old and new) carry the current `course_scope`.
  - The existing schedule export currently ignores the param; making it honor
    the scope is **out of scope** here — the round-trip format is
    whole-semester by design. It keeps exporting everything.

## 3. CSV export (one row per section)

- **Route:** `get :export_sections` member on `resources :semesters`, next to
  the existing `get :export`.
- **Exporter:** `app/services/exporters/semester_sections_exporter.rb`
  following `Exporters::ScheduleExporter` (subclass of `Exporters::Base`,
  `HEADERS` + `filename` + `rows`). Takes `(semester, course_scope:)`.
- **Filename:** `sections_<year_be>_<semester_number>.csv` (add `_dept`
  suffix when scoped, e.g. `sections_2568_1_dept.csv`).
- **Headers/row:**

  ```
  course_no,course_name,section,teachers,schedule,enrolled,max,status
  2110101,Comp Prog,1,"NNN, PKY",Mon/Wed 09:00-10:30 ENG4-303,45,50,confirmed
  ```

  - `teachers` — comma-joined `initials.presence || display_name_th`.
  - `schedule` — same grouped format as the table cell (plain text).
  - `enrolled` / `max` — raw integers, blank when nil.
  - `status` — raw enum value (lowercase), machine-friendly.
- **Offerings with zero sections** still emit one row with blank
  section/teachers/schedule/enrolled/max so the export is a complete offering
  list for the term.
- **Buttons:** relabel the existing button **"Export Schedule"** (round-trip
  format) and add **"Export Sections"** for the new CSV, both in the header
  button row. Distinct labels are the fix for the two-exports ambiguity.

## 4. Code shape

- **Formatting logic** lives in a helper (`CourseOfferingsHelper`):
  `section_schedule_summary(section)` returning the grouped-slots plain text,
  plus a small builder for the full table line. The exporter reuses the same
  schedule-summary text via the helper (include the module) so table and CSV
  can't drift.
- **Controller** (`semesters_controller.rb#show`): parse `@course_scope`,
  filter, and eager-load
  `includes(:course, sections: [{ teachings: :staff }, { time_slots: :room }])`.
  New `export_sections` action sends the exporter's CSV.

## 5. Backlog check (docs/backlog.md)

- **Item 1 — entity→report cross-links (applied):** semesters/show gains
  pre-filled links to `/schedules/teaching_matrix?run=1&year=<year_be>&semester_number=<n>`
  (who teaches what, dept-wide) and `/schedules/conflicts?semester_id=<id>`
  (double bookings) — small links near the card title. Extend the backlog
  seed list with this entry. (Verify conflicts' actual param names at
  implementation time; `run=1` only if the conflicts form uses the
  run-param convention.)
- **Item 2 — report↔entity overlap (checked, no action):** no registry report
  lists offerings-with-sections per term; Teaching Matrix has a different
  shape (staff × course). Nothing retired.

## 6. Testing (deferred until after implementation, per project convention)

- Helper unit tests: slot grouping (same time+room across days collapses;
  different room splits), TBA fallback, enrollment `?` rendering, no-slot /
  no-teaching omissions.
- Exporter test: per-section rows, zero-section offering row, scope
  filtering, filename.
- System test: semester page shows section lines; scope toggle narrows the
  table; both export buttons present.

## Out of scope

- Section/offering remarks in the table (visible on the offering show page).
- Section-level sorting in the DataTable.
- Making the schedule (round-trip) export honor `course_scope`.
- Any change to the offerings data model.
