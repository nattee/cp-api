# Course Group Display & Curriculum Management — Design

**Date:** 2026-07-06
**Status:** Approved (pending spec review)

## Problem

The many-to-many relation between Program and Course (`program_courses`) has a
`course_group_code` column meant to tag each pairing with its curriculum group
(compulsory, elective, approved elective, …), but no page displays this
information and nothing populates the column. The data exists — just in the
wrong places:

- `program_courses.course_group_code` / `course_type`: **NULL in all 553 rows.**
  Populating them was deferred to "Project 2 (ChulaBooster)" by the m2m remodel
  (see `2026-06-30-course-program-m2m-remodel-design.md`) and never ran.
- `courses.course_group` (legacy string on Course, per course revision, not per
  pairing): 257 courses carry values like `4784-C`, `3736-ELEC2` from old CSV
  imports. Format: `<program_code>-<group suffix>`.
- ChulaBooster snapshot (`20260706-041925`): 172 `program_courses` rows with
  per-pairing `course_group_code` for programs 4784 (CP 2566) and 3736
  (CP 2561). `course_type` is always `9` (meaning unknown — carries no signal).

Additional findings that shaped scope:

- **Zero courses currently link to more than one program** — each curriculum
  revision has its own Course row imported against a single program. 296 links
  point at the `0000 OTHER` placeholder program.
- **The course edit form is destructive for multi-program courses**: it renders
  a single-select of `course.programs.first` and saves via
  `program_ids = [that one]`, silently deleting every other link
  (`courses_controller.rb`). Once tags are populated, saving would also destroy
  them.
- Group suffixes seen in data: `C, ELEC, ELEC2, MS, LANG, GLANG, GSP, SP, ENG, 21`.

## Decisions (made with dae)

1. **Populate from both sources**: CB sync is primary; a one-time backfill from
   legacy `courses.course_group` fills pairings CB doesn't cover.
2. **Display on both pages**: Program show page gets a Curriculum section;
   Course show page shows the group tag per program.
3. **Labels via frozen constant**, keyed by **full code** (per-program mapping,
   e.g. `"4784-C"` and `"3736-C"` are separate entries). An editable
   `CourseGroup` reference table was considered and rejected (YAGNI): labels
   change roughly never, the sole maintainer is a Rails dev, and the constant
   is this repo's stated convention. Promoting to a table later is mechanical
   because all lookups go through one helper.
4. **Links become manageable from the program page** (add/edit tag/remove), and
   the destructive course form is fixed.

## Part 1 — Data & population

### Schema

**No changes.** Data lands in existing columns:

- `program_courses.course_group_code` — raw tag string, e.g. `"4784-C"`.
- `program_courses.course_type` — mirrored raw from CB (no UI; always 9 today).
- `courses.course_group` — **deprecated**; kept as backfill source. Drop in a
  later cleanup once CB coverage is proven. Its display row on the course show
  page is removed (Part 2).

### Labels

`ProgramCourse::COURSE_GROUP_LABELS` — frozen hash, full code → label.
**Hash insertion order defines display order** on the curriculum page
(compulsory first, then electives, then GenEd groups). Initial entries: the 14
codes in today's data, labels best-guess (`C` → Compulsory, `ELEC` → Elective,
…) — **dae corrects the guesses during implementation review**.

A single helper (e.g. `course_group_label(code)`) is the only lookup point:

- known code → label from the constant
- unknown code → raw suffix (code minus `<program_code>-` prefix), so new CB
  data never breaks the page
- blank → "Ungrouped"

### CB sync — `Chulabooster::ProgramCourseSync`

New sync class + `bin/rails chulabooster:sync_program_courses` rake task. Same
contract as the other syncs: **dry-run by default, `COMMIT=1` to write,
`SNAPSHOT_DIR=` to run offline.**

Per CB `program_courses` row:

1. Resolve program by `program_id` → local `program_code`; resolve course by
   `course_no` + revision year (via `Convert.parse_course_id` /
   `course_no` field, as in the existing mapper).
2. Unresolvable program or course → count + report row (report-only CSV, same
   `ReportWriter` machinery), skip.
3. `find_or_create` the `ProgramCourse` pairing (**additive** — never deletes
   local links CB lacks).
4. Tag policy (non-destructive, matches repo-wide rule):
   - local tag blank → fill from CB (`course_group_code` + `course_type`).
   - local tag present and equal → no-op.
   - local tag present and **different** → **report-only CSV row, never
     overwrite** (protects future manual edits).

### Legacy backfill — one-time rake task

Runs **after** the CB sync so CB wins where both know the answer. Same
dry-run-default / `COMMIT=1` contract. For each Course with a legacy
`course_group` string:

1. Parse `<program_code>-<suffix>`; resolve the program by prefix. Unparseable
   value or unknown program code → report, skip.
2. `find_or_create` the pairing to the **parsed** program — this matters
   because many existing links point at `0000 OTHER`, not the program named in
   the tag. Existing `OTHER` links are left alone (report-only note).
3. Fill `course_group_code` (full original string) **only if blank**; differing
   existing tag → report, never overwrite.

## Part 2 — Display & editing UI

### Program show page — Curriculum card

New card placed directly after the details card (before the student charts).

- **One single table** for all groups, using `.table-group-header` +
  `.table-group-spacer` rows (canonical usage: Course History tables in
  `students/show`). Do NOT use separate tables per group.
- Group order: `COURSE_GROUP_LABELS` insertion order → unknown codes
  alphabetically → "Ungrouped" last. Group header: label + count, raw code
  muted beside the label.
- Columns: Course No, Name (link to course), Credits, admin-only Actions.
- **No DataTable** — client-side sorting would tear group rows apart (same
  reason the grade tables don't use it).
- Card title row: `%h5.card-title` + resource icon + "Curriculum" + total
  count; admin-only "Add Course" button.
- Empty state: muted "No courses linked to this program." paragraph.

### Link management (admin-only)

Nested routes:

```ruby
resources :programs do
  resources :program_courses, only: %i[new create edit update destroy]
end
```

`ProgramCoursesController` requires admin for **all** actions (every action
mutates). Rooms-style inline editing:

- `turbo_frame_tag "program_course_form"` placeholder inside the Curriculum
  card; "Add Course" and per-row edit links target the frame
  (`data-turbo-frame`); the form targets `_top` so save redirects to the full
  program page.
- **Add form**: Select2 dropdown of courses **not yet linked** to this program
  (label: `course_no — name (rev year)`), group-tag text field with `datalist`
  suggestions (codes already used by this program + constant keys matching this
  program's prefix).
- **Edit form**: course read-only, tag editable.
- **Remove**: ghost danger button + confirm; destroys the link only, never the
  course. Model uniqueness (`course_id` scoped to `program_id`) already guards
  duplicates; the form re-renders with errors on violation.

### Course show page

- Each program in the existing programs list gets a badge with this pairing's
  group label — new `.badge-course-group` SCSS class (one concept = one class,
  frosted style).
- The legacy `Course Group` dt/dd row is removed (redundant once per-program
  tags display).

### Course form fix

- Single-select becomes Select2 **multi-select** (`multiple: true`) pre-filled
  with all linked programs; controller permits `program_ids: []`.
- `program_ids=` keeps join rows for programs that remain selected (tags
  survive), deletes deselected, adds new links untagged (tag set later from
  the program page).

## Error handling summary

| Case | Behavior |
|---|---|
| CB row's program/course not found locally | count + report CSV, skip |
| Local tag differs from CB / legacy value | report-only, never overwrite |
| Unparseable legacy `course_group` string | report, skip |
| Unknown code in UI | raw suffix fallback, grouped after known groups |
| Blank tag in UI | "Ungrouped" section, listed last |
| Duplicate link via add form | model validation error, form re-renders |

## Testing (deferred until feature complete, per dae's flow)

- **Model**: label helper (known code, unknown code suffix fallback, blank);
  group ordering logic.
- **Sync/backfill**: fixture-driven — creates missing pairing, fills blank tag,
  never overwrites differing tag, reports unresolvable rows.
- **System**: curriculum card renders groups in constant order with counts;
  admin add/edit/remove link flow; non-admin sees no controls; **regression** —
  editing a multi-program course via the course form no longer drops links.

## Out of scope

- Dropping `courses.course_group` (later cleanup).
- `course_type` semantics (always 9; ask CB team — mirrored raw only).
- Editable `CourseGroup` reference table (future promotion path if label churn
  becomes real).
- Group data for programs beyond 4784/3736 (arrives automatically with future
  CB snapshots + re-sync).
