# Schedule Reports

**Status: Implemented**

Cross-cutting queries and visualizations for the teaching schedule data. This is **Layer 3** of the teaching schedule feature — see `docs/teaching-schedule.md` for the data model and CRUD (Layers 1-2).

## Prerequisites

- All 6 teaching schedule models exist and have data (Semester, Room, CourseOffering, Section, TimeSlot, Teaching)
- Layer 2 embedded sections on Staff/Course/Student show pages are done

## Reports Overview

| # | Report | Filters | Display | Primary user |
|---|--------|---------|---------|-------------|
| 1 | **Room Schedule** | room, semester | week calendar | admin |
| 2 | **Staff Schedule** | staff, semester | week calendar | staff, admin |
| 3 | **Staff Workload** | staff, year range | summary table | admin |
| 4 | **Curriculum Calendar** | course set / program+year, semester | week calendar | admin |
| 5 | **Student Timetable** | student, semester | week calendar + grades | student, advisor |
| 6 | **Conflict Detection** | semester | conflict list | admin |

## Shared Component: Week Calendar

Reports 1, 2, 4, and 5 all render a **week calendar grid**. This should be a single reusable partial.

### Layout

```
         Mon        Tue        Wed        Thu        Fri        Sat
 8:00  ┌─────────┐
       │ 2110101 │
 8:30  │ Sec 1   │
       │ ENG4-303│
 9:00  └─────────┘
 9:30            ┌─────────┐
                 │ 2110201 │
10:00            │ Sec 2   │
                 │ ENG4-LAB│
10:30            └─────────┘
  ...
```

- Columns: Mon–Sat (skip Sunday unless time slots exist on Sunday)
- Rows: 30-minute increments, 8:00–18:00 (or auto-fit to data range)
- Each block shows: course name/number, section, room (varies by report context)
- Blocks span multiple rows based on duration
- Color-coded by course or section (consistent palette)

### Implementation

- **Partial**: `app/views/shared/_week_calendar.html.haml`
- **Input**: array of time slot objects (or hashes) with day, start_time, end_time, and display fields
- **Rendering**: server-side HTML table with CSS for positioning. No JS calendar library needed — the grid is static once rendered.
- **CSS**: absolute positioning within day columns based on time. Blocks use `top` and `height` calculated from start/end times relative to the grid range.
- **Print-friendly**: should look good when printed (white background override, borders)

### Calendar data structure

```ruby
# Each entry passed to the partial:
{
  day_of_week: 1,           # 0=Sun..6=Sat
  start_time: "09:00",
  end_time: "10:30",
  label: "2110101",         # primary text
  sublabel: "Sec 1",        # secondary text
  detail: "ENG4-303",       # tertiary text (room, staff, grade, etc.)
  color_key: "2110101",     # determines block color
  url: "/course_offerings/5" # optional link
}
```

Reports build this array differently depending on their context, then pass it to the same partial.

---

## Report 1: Room Schedule

**Purpose**: Show what's happening in a room across the week for a given semester. Useful for checking room availability and utilization.

**URL**: `GET /schedules/room`

**Filters**:
- Semester (required) — Select2 dropdown
- Room (required) — Select2 dropdown, filtered after semester is selected to show only rooms with time slots in that semester

**Display**:
- Week calendar where each block shows: course number, section number, staff name(s)
- Below the calendar: utilization summary — hours used vs. available hours (capacity × weekday hours), as a simple stat card

**Query**:
```ruby
TimeSlot.joins(section: { course_offering: :course })
        .where(room: room, section: { course_offering: { semester: semester } })
        .includes(section: [:teachings, { course_offering: :course }])
```

---

## Report 2: Staff Schedule

**Purpose**: Show a staff member's weekly teaching schedule for a semester. Staff can view their own; admins can view anyone's.

**URL**: `GET /schedules/staff`

**Filters**:
- Semester (required) — Select2 dropdown
- Staff (required) — Select2 dropdown

**Display**:
- Week calendar where each block shows: course number, section number, room
- Below the calendar: load summary — total load_ratio across all teachings this semester

**Query**:
```ruby
# Get sections this staff teaches
section_ids = Teaching.where(staff: staff)
                      .joins(section: :course_offering)
                      .where(course_offerings: { semester: semester })
                      .pluck(:section_id)

# Get all time slots for those sections
TimeSlot.where(section_id: section_ids)
        .includes(section: { course_offering: :course }, room: true)
```

---

## Report 3: Staff Workload

**Purpose**: Summary table of teaching load across semesters. For admin review of workload distribution.

**URL**: `GET /schedules/workload`

**Filters**:
- Year range (required) — start year and end year (B.E.), defaults to current year
- Staff type filter (optional) — lecturer, adjunct, etc.

**Display**: DataTable, not a calendar.

| Staff | 2568/1 | 2568/2 | 2568/3 | Total |
|-------|--------|--------|--------|-------|
| ผศ.ดร. Smith | 1.5 | 1.0 | 0.5 | 3.0 |
| รศ.ดร. Jones | 2.0 | 1.5 | — | 3.5 |

- Each cell is the sum of `load_ratio` for that staff in that semester
- Color-code cells: green (normal), yellow (high), red (overloaded) based on configurable thresholds
- Click a cell to jump to that staff's schedule (Report 2) for that semester

**Query**:
```ruby
Teaching.joins(:staff, section: { course_offering: :semester })
        .where(semesters: { year_be: year_range })
        .group(:staff_id, "semesters.year_be", "semesters.semester_number")
        .sum(:load_ratio)
```

---

## Report 4: Curriculum Calendar

**Purpose**: View the weekly timetable for a set of courses. Used for curriculum planning — "if a student takes these courses, what does their week look like?"

**URL**: `GET /schedules/curriculum`

**Filters**:
- Semester (required) — Select2 dropdown
- Course selection — one of:
  - **Manual**: Select2 multi-select for courses
  - **Preset** (future): program + year → auto-selects required courses for that curriculum year

**Display**:
- Week calendar with all selected courses overlaid
- Color-coded by course
- Overlapping blocks are visually flagged (conflict highlight)
- Section selector per course (if a course has multiple sections, user can pick which section to show)

**Query**:
```ruby
TimeSlot.joins(section: { course_offering: :course })
        .where(course_offerings: { semester: semester, course_id: course_ids })
        .includes(section: { course_offering: :course }, room: true)
```

### Future: Course presets

A "course preset" is a saved set of courses associated with a program + curriculum year (e.g., "CPE Year 2 required courses"). This could be:
- A new model (`CoursePreset` has_many courses, belongs_to program, year label)
- Or derived from curriculum data if that exists elsewhere

Not in initial scope — start with manual multi-select. Design preset model later when curriculum data is better understood.

---

## Report 5: Student Timetable

**Purpose**: Show a student's weekly schedule for a semester, including grades if available.

**URL**: `GET /schedules/student`

**Filters**:
- Semester (required) — Select2 dropdown
- Student (required) — Select2 dropdown (search by student ID or name)

**Display**:
- Week calendar where each block shows: course number, section number, room
- Grade badge overlay on each block (if grade exists for that course+semester)
- Below the calendar: table of enrolled courses with grade, credits, and staff

**Linking grades to schedule**: The `Grade` model has `student_id`, `course_id`, `year`, `semester` — and will gain a nullable `section_id` FK. The `CourseOffering` has `course_id` and `semester_id` (which has `year_be` and `semester_number`). We join through course + semester fields to connect a student's grades to the schedule.

**Section resolution** (in order):
1. If `grade.section_id` is set → use that section
2. Otherwise → use the **first section** (lowest `section_number`) for that course offering
3. If no course offering exists for that semester → show the course without schedule data

**Query**:
```ruby
semester = Semester.find(semester_id)
grades = Grade.where(student: student, year: semester.year_be, semester: semester.semester_number)
              .includes(:course)

grades.map do |grade|
  offering = CourseOffering.find_by(course: grade.course, semester: semester)
  next unless offering

  section = if grade.section_id
              grade.section
            else
              offering.sections.order(:section_number).first
            end

  # Build calendar entries from section.time_slots
end
```

---

## Report 6: Conflict Detection

**Purpose**: Find scheduling conflicts — rooms double-booked or staff double-booked in overlapping time slots.

**URL**: `GET /schedules/conflicts`

**Filters**:
- Semester (required) — Select2 dropdown
- Conflict type: Room conflicts, Staff conflicts, or both

**Display**: Table of conflicts, not a calendar.

| Type | Day | Time | Conflict | Details |
|------|-----|------|----------|---------|
| Room | Mon | 9:00-10:30 | ENG4-303 | 2110101 Sec 1 vs 2110327 Sec 2 |
| Staff | Tue | 13:00-14:30 | ผศ.ดร. Smith | 2110101 Sec 1 vs 2110432 Sec 1 |

**Room conflict**: two time slots in the same room, same day, overlapping time range.
**Staff conflict**: a staff member teaches two sections whose time slots overlap on the same day.

**Query (room conflicts)**:
```ruby
# Self-join time_slots where same room, same day, overlapping times
# Overlap: a.start_time < b.end_time AND b.start_time < a.end_time
TimeSlot.joins(section: :course_offering)
        .where(course_offerings: { semester: semester })
        .where.not(room_id: nil)
        .select("time_slots.*")
        .group_by { |ts| [ts.room_id, ts.day_of_week] }
        .flat_map { |_, slots| find_overlaps(slots) }
```

**Query (staff conflicts)**:
```ruby
# Find staff who teach multiple sections with overlapping time slots
Teaching.joins(section: [:time_slots, :course_offering])
        .where(course_offerings: { semester: semester })
        .group_by(&:staff_id)
        .flat_map { |_, teachings| find_staff_overlaps(teachings) }
```

---

## Routes

```ruby
namespace :schedules do
  get :room
  get :staff
  get :workload
  get :curriculum
  get :student
  get :conflicts
end
```

All under one `SchedulesController` or separate controllers per report. Single controller is simpler since they're all read-only and share filter patterns.

## Controller

```ruby
class SchedulesController < ApplicationController
  # All actions are read-only, no require_admin needed for viewing
  # (staff should see their own schedule, admins see everything)

  def room;       end
  def staff;      end
  def workload;   end
  def curriculum; end
  def student;    end
  def conflicts;  end
end
```

Authorization: all users can view reports. If needed later, restrict certain reports to admin.

## Sidebar Navigation

Add under the "Teaching" section header (after Semesters and Rooms):

```haml
%li.nav-item
  = link_to schedules_room_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'schedules'}" do
    = resource_icon("schedules")
    Schedules
```

One sidebar entry "Schedules" that leads to a landing page with cards linking to each report. This avoids adding 6 items to the sidebar.

Add to `ApplicationHelper::RESOURCE_ICONS`:
```ruby
"schedules" => "date_range",
```

### Schedules landing page

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ 🏫 Room Schedule │  │ 👤 Staff Schedule│  │ 📊 Staff Workload│
│                  │  │                  │  │                  │
│ View room usage  │  │ Weekly timetable │  │ Load summary     │
│ by semester      │  │ for a staff      │  │ across semesters │
└──────────────────┘  └──────────────────┘  └──────────────────┘
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ 📅 Curriculum    │  │ 🎓 Student       │  │ ⚠️ Conflicts     │
│    Calendar      │  │    Timetable     │  │                  │
│ Plan course sets │  │ Student weekly   │  │ Room & staff     │
│ for a semester   │  │ schedule + grades│  │ double bookings  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

## Implementation Order

1. **Week calendar partial** — the shared component, built first
2. **Room Schedule** — simplest report, good for validating the calendar partial
3. **Staff Schedule** — similar to room, adds staff filter
4. **Conflict Detection** — pure table, no calendar, but high value
5. **Staff Workload** — pure table, different shape
6. **Curriculum Calendar** — adds multi-select and section picker complexity
7. **Student Timetable** — depends on grade-to-section linking decision

## Testing

### Model/query tests

Test the query logic for each report as standalone methods (e.g., on the model or in a service object):
- Room schedule query returns correct time slots for a room+semester
- Staff schedule query returns correct time slots for a staff+semester
- Workload summary correctly sums load_ratio grouped by staff+semester
- Conflict detection finds overlapping time slots (room and staff)
- Conflict detection does NOT flag non-overlapping adjacent slots (9:00-10:00 and 10:00-11:00)

### System tests

- Room schedule: select semester + room, see calendar with correct blocks
- Staff schedule: select semester + staff, see calendar
- Workload: select year range, see summary table with correct totals
- Conflict detection: with known conflicting fixtures, see conflicts listed

## Design Decisions

### 1. Student section assignment

The data source currently doesn't include section info, but it exists in practice (a student must be in a section to get a grade). Plan:

- **Add nullable `section_id` FK to Grade** — migration adds the column, no backfill needed yet
- **Default behavior**: when section is unknown, assume the **first section** (lowest `section_number` for that offering), not necessarily section "1" — section numbers can be non-sequential (e.g., 1, 5, 99, 302)
- **Import change**: modify the Grade importer to accept an optional section column. If present, look up the section; if absent, leave `section_id` null (and the report falls back to first section)
- **Future**: coordinate with data source team to include section in the export

### 2. Course presets

Manual multi-select (Select2) for now. Preset model to be designed later when curriculum data requirements are clearer.

### 3. Workload thresholds

User-selectable on the report page, no database storage. Defaults:
- **Low**: total load_ratio < 1
- **Normal**: 1 – 2
- **High**: > 2

Render as input fields with these defaults so the user can adjust per-session.

### 4. Access control

Role-based, using the existing `User#role` field:
- **admin**: all reports
- **editor**: all reports
- **viewer**: all reports

Students can't log in currently. When student login is added in the future, restrict student timetable to their own data. Design the controller to check `current_user.role` so adding restrictions later is a one-line change, not a refactor.

## Implementation Status

All 6 reports are implemented. Requires user testing with real data.

| Report | Status | Notes |
|--------|--------|-------|
| Room Schedule | Done | Week calendar, room+semester filter |
| Staff Schedule | Done | Week calendar + load summary |
| Staff Workload | Done | DataTable, year range + staff type filter, color thresholds |
| Curriculum Calendar | Done | Multi-select courses, color-coded by course |
| Student Timetable | Done | Grade badges, section resolution (grade.section_id → first section fallback) |
| Conflict Detection | Done | Room + staff overlaps, strict overlap (adjacent slots NOT flagged) |

### Implementation notes

- **Routes**: `controller :schedules do ... end` pattern (not `namespace`), all under `SchedulesController`
- **Week calendar partial**: `app/views/shared/_week_calendar.html.haml` — accepts `entries` array, 12-color palette, auto-fit time range, CSS absolute positioning
- **Conflict algorithm**: `a.start_time < b.end_time && b.start_time < a.end_time` — strict inequality means 09:00-10:00 and 10:00-11:00 are NOT overlapping
- **Workload thresholds**: user-adjustable via form fields, defaults `low_threshold=1`, `high_threshold=2`, cells colored with Bootstrap `table-success` / `table-danger`
- **Landing page**: `/schedules` with 6 report cards linking to individual reports
