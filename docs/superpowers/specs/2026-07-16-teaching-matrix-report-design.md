# Teaching Matrix report (staff × course section counts)

**Date:** 2026-07-16
**Status:** Approved

## Motivation

"Who taught what" across the department is currently answerable only one slice
at a time: per staff (staffs/show Teaching History), per course
(`Reports::CourseTeachers`), or per load-number (schedules/workload, which
shows *how much* but not *which courses*). There is no single view of the whole
department's teaching assignments for a term or year.

At the same time there is a standing concern that the report count keeps
growing (docs/backlog.md item 2). This feature is therefore a **consolidation,
not an addition**: the new matrix fully absorbs the set-level use of
`Reports::CourseTeachers` (one matrix column = that entire report for a term),
whose retirement backlog item 2 already anticipated. Net web-report count
stays flat.

### Overlap analysis (why this doesn't duplicate existing pages)

- **staffs/show Teaching History** — semesters × courses for ONE staff
  ("tell me about X"). The matrix is staff × courses for one term/year
  ("who/which across a set"). Complementary per the backlog's own taxonomy;
  they share only the visual idiom (reuse `.teaching-history-table` styling).
- **`Reports::CourseTeachers`** — absorbed; retired as part of this work
  (see Bundle below).
- **`Reports::StaffCoursesByYear`** — one matrix row (year-scoped) covers its
  course list + section counts, but it uniquely offers Enrolled/Max,
  co-lecturers, CSV. Keep, per backlog item 2. No change.
- **schedules/workload** — staff × semester with metric toggle; the matrix is
  the per-course drill-down of a single term/year. Row totals of the matrix
  equal workload's "sections" metric for that scope. Complementary; workload
  keeps the ranking/sorting job, so the matrix needs no sorting of its own.

## Report definition

### Route + controller

- `GET /schedules/teaching_matrix` → `SchedulesController#teaching_matrix`,
  added to the existing `controller :schedules do` block in `config/routes.rb`
  (path helper `schedules_teaching_matrix_path`). 7th schedules report; add
  its tile/link to `app/views/schedules/index.html.haml`.
- Auth: same as the other schedules reports (login required, no admin gate —
  read-only).

### Params

| param | values | default |
|---|---|---|
| `year` | B.E. year | latest `semesters.year_be` that has any `Teaching` |
| `semester_number` | `1`/`2`/`3` or blank | blank = whole academic year |
| `course_scope` | `dept` (course_no LIKE `2110%`) / `all` | `dept` |

Defaults mean the page renders a useful matrix on first load (latest teaching
year, all its semesters, department courses). Invalid/blank params fall back
to defaults. Data note (2026-07-16): a semester has ~40–67 courses with
teachings and ~40 staff; `all` adds only ~3–5 non-2110 engineering courses;
non-21 courses with teachings are currently zero.

### Query

One query, in the controller like the other schedules reports:

- `Teaching.joins(section: { course_offering: [:course, :semester] })` filtered
  by `semesters.year_be`, optional `semesters.semester_number`, optional
  `courses.course_no LIKE '2110%'`, with includes for staff.
- **Columns**: distinct `course_no` in scope, sorted ascending. `course_no` is
  the cross-revision key (per Data Model Conventions) — revisions of the same
  course merge into one column.
- **Rows**: staff having ≥1 teaching in scope, sorted by `display_name_th`.
- **Cells**: count of distinct sections the staff teaches for that course_no
  in scope. Tooltip lists section numbers; when the scope is a whole year,
  qualify by term (e.g. `1/2568: sec 1, 33 · 2/2568: sec 2`); single-term
  scope matches the staff-page style (`Sections 1, 33`).
- **Σ column**: last column = total distinct sections per staff row.

### View

`app/views/schedules/teaching_matrix.html.haml`:

- Filter card on top (form_with GET, like workload): Year number field,
  Semester select (blank = All), course-scope select (Department 2110xxx /
  All courses), View button.
- Matrix table reusing the staffs/show idiom: `.teaching-history-table`,
  rotated course_no headers (`.th-rotated`) linking to the course page with
  the course name as `title`; staff cell links to `staff_path`; empty cells
  blank.
- **Plain table, no DataTables**: ~40 rows needs no pagination/search, course
  columns must not grow sort icons on rotated headers, and load-ranking is
  workload's job. (`datatable_controller` also can't disable ordering on a
  column range — not worth extending for this.)
- Empty scope → muted "No teaching data found." card, workload-style.

## Bundle: absorb + retire `Reports::CourseTeachers`

1. **courses/show Offerings table gains a "Teachers" column** — distinct staff
   across the offering's sections, shown as initials (fallback
   `display_name_th`), each linking to the staff page. This closes the gap
   backlog item 2 named as the retirement blocker ("section counts but not
   teachers").
2. **Retire the report**: delete `app/services/reports/course_teachers.rb`,
   its line in `Reports::Registry::REPORTS`, and its assertions in
   `test/services/reports/registry_test.rb`. The LINE bot is unaffected (it
   uses `GradeStats::` services, not `Reports::` — backlog item 2).

## Cross-links, docs, backlog (triggered items)

- **staffs/show** per-semester Teaching card links to the matrix pre-filled
  with the selected semester's year + semester_number ("View department-wide
  matrix" or similar). Record in backlog item 1's seed list.
- **backlog item 1**: drop the `courses/show → course_teachers` seed entry
  (report retired); add the staffs/show → teaching_matrix link entry.
- **backlog item 2**: mark `course_teachers` retired (date + how); add
  `teaching_matrix` as a set/aggregate report with no single-entity anchor —
  "keep regardless".
- **docs/schedule-reports.md**: add a Teaching Matrix section (purpose,
  params, query shape).
- **CLAUDE.md**: "6 read-only reports" → 7 in the Teaching Schedule section;
  remove/adjust any `course_teachers` mention if present.

## Testing

Written after the feature is finished (owner's flow), planned as:

- **Controller test** (`test/controllers/schedules_controller_test.rb`
  additions): teaching_matrix renders; year/semester filtering scopes rows;
  `course_scope=dept` excludes non-2110 fixtures; defaults applied when
  params absent; empty scope shows the no-data message.
- **Controller/integration**: courses/show shows the Teachers column;
  reports index no longer lists "Who teaches this subject".
- **System test** (happy path): visit matrix with fixtures, assert a known
  staff row shows the right count in the right course column and the Σ total.

## Out of scope

- CSV export of the matrix (workload has none either; revisit on demand).
- Cell links to `schedules/staff` week view (tooltip covers section detail).
- Column-total footer row.
- Staff-type filter (rows are inherently staff with teachings; add later if
  externals ever pollute the matrix).
