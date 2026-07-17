# Backlog

Standing items that are not scheduled work but must be **re-checked whenever the
areas they touch change**. Each item names its trigger. When a trigger fires
(you're adding/changing a matching page or report), re-read the item and either
apply it to the thing you're building, extend the item's list, or consciously
skip it — don't let it silently rot.

## 1. Entity page → report cross-links (recurring)

**Trigger: any new/changed report, any new/changed entity show page.**

Entity pages answer "tell me about X"; reports answer "who/which/how many
across a set". Where a report answers a question *adjacent* to an entity page,
the entity page should link to it — with params pre-filled and a short
explanation of what the report adds. The report form already reads its params
from the query string, so links like
`/reports/staff_courses_by_year?run=1&staff=NNN&year=2568` pre-fill AND run
directly.

Seed list (2026-07-09):

- **staffs/show** (per-semester Teaching card) → `staff_courses_by_year`
  pre-filled with the staff's initials + the selected semester's year:
  adds class sizes (Enrolled / Max), co-lecturers, and CSV export that the
  card doesn't show.
- **courses/show** → `failing_students` (course_no pre-filled).
- **program_groups/show** → `semester_grade_distribution` and `cohort_gpa`
  (program_group pre-filled).
- **data_sources/index** → `data_coverage`: the source docs answer "how does
  data get in"; the report answers "did it actually arrive for each term"
  (per-term counts with gaps flagged). Link added 2026-07-16.
- **staffs/show** (per-semester Teaching card) → `/schedules/teaching_matrix`
  pre-filled with the selected semester: the department-wide view of the same
  term. Link added 2026-07-16.
- **semesters/show** → `/schedules/teaching_matrix` (year + semester_number
  pre-filled) and `/schedules/conflicts` (semester_id pre-filled): the
  dept-wide who-teaches-what and double-booking views for the term shown on
  the page. Links added 2026-07-17.

## 2. Report ↔ entity page overlap review (recurring)

**Trigger: any new report; periodically when entity pages grow new cards.**

Reports whose primary parameter is a single entity drift into duplicating that
entity's show page. When one has been fully absorbed, retire its web form from
the registry (the LINE bot does NOT depend on `Reports::` classes — it uses the
shared `GradeStats::` services — so retiring a web report doesn't break the bot).

Status as of 2026-07-09:

- `course_teachers` — **retired 2026-07-16**: courses/show Offerings gained a
  Teachers column and the teaching-matrix schedules report covers the
  cross-course view.
- `staff_courses_by_year` — largely absorbed by staffs/show (per-semester card
  + teaching-history matrix), but uniquely offers Enrolled/Max, Other
  Lecturers, and CSV. Keep for now; revisit if those move onto the staff page.
- `failing_students` — partial overlap (courses/show Grades table filters by
  term but not by grade value). Keep.
- `semester_grade_distribution`, `cohort_gpa`, `group_credit_shortfall`,
  `thesis_credits` — genuine set/aggregate reports, no entity anchor. Keep
  regardless.
- `data_coverage` — set/aggregate report (terms × datasets), no single-entity
  anchor. Keep regardless.
- `teaching_matrix` (at `/schedules`, not the registry) — set/aggregate report
  (staff × course per term/year), no single-entity anchor. Keep regardless.

## How to add an item

One `## N. Title (recurring|one-shot)` section, a bold **Trigger:** line, then
enough context that a future session can act without this conversation.
