# Teaching Schedule

Record which courses are offered each semester, their sections, teaching schedules, and staff assignments.

## Scope

This feature has three layers. This doc covers **Layers 1 and 2**. Layer 3 has its own design doc.

| Layer | What | Doc |
|-------|------|-----|
| **1. CRUD** | Data entry: Semester, Room, CourseOffering (with nested Sections, TimeSlots, Teachings) | this doc |
| **2. Embedded sections** | Schedule info on existing show pages (Staff → teachings, Course → offerings, Student → timetable) | this doc |
| **3. Reports** | Cross-cutting queries: room schedule, staff workload, curriculum calendar, student timetable, conflict detection | `docs/schedule-reports.md` |

Layer 3 is designed separately because the report UIs benefit from having real data in the system first.

## Business Rules

- Each course may be offered in any semester (year + semester number 1/2/3)
- A course can only be offered **once per semester** (unique on course + semester)
- Each offering has one or more sections (numbered sequentially)
- Each section has one or more time slots (day of week, start time, end time, room)
- Each time slot has one or more staff assigned, each with a teaching load ratio (e.g. 0.5 = 50% load)
- A section may have a remark (free text)

## Data Model

6 new tables. Migration order follows foreign key dependencies.

```
Semester ──< CourseOffering >── Course
                  │
               Section ──< Teaching >── Staff
                  │
               TimeSlot >── Room (optional)
```

### semesters

| Column          | Type    | Constraints            |
|-----------------|---------|------------------------|
| year_be         | integer | not null               |
| semester_number | integer | not null               |
| timestamps      |         |                        |

- Unique index: `[year_be, semester_number]`
- `semester_number` is 1, 2, or 3 (same as `Grade::SEMESTERS`)

**Why a separate model instead of inline year+semester like Grade?**
Semester is a navigational parent — the UI starts with "pick a semester", and multiple CourseOfferings reference the same semester. A model avoids scattered year/semester pairs and enables a semester index/show as entry points.

### rooms

| Column      | Type    | Constraints              |
|-------------|---------|--------------------------|
| building    | string  | not null                 |
| room_number | string  | not null                 |
| room_type   | string  | nullable                 |
| capacity    | integer | nullable                 |
| timestamps  |         |                          |

- Unique index: `[building, room_number]`
- `room_type`: lecture, lab, seminar, other
- Separate model because rooms are reusable across time slots and semesters

### course_offerings

| Column      | Type   | Constraints                      |
|-------------|--------|----------------------------------|
| course_id   | bigint | not null, FK courses             |
| semester_id | bigint | not null, FK semesters           |
| status      | string | not null, default `"planned"`    |
| remark      | text   | nullable                         |
| timestamps  |        |                                  |

- Unique index: `[course_id, semester_id]`
- Index: `semester_id`
- `status`: planned, confirmed, cancelled

### sections

| Column             | Type    | Constraints                  |
|--------------------|---------|------------------------------|
| course_offering_id | bigint  | not null, FK course_offerings|
| section_number     | integer | not null                     |
| remark             | text    | nullable                     |
| enrollment_current | integer | nullable                     |
| enrollment_max     | integer | nullable                     |
| timestamps         |         |                              |

- Unique index: `[course_offering_id, section_number]`
- Enrollment columns are populated by the scraper (see `docs/schedule-scraper.md`)

### time_slots

| Column      | Type    | Constraints              |
|-------------|---------|--------------------------|
| section_id  | bigint  | not null, FK sections    |
| room_id     | bigint  | nullable, FK rooms       |
| day_of_week | integer | not null (0=Sun..6=Sat)  |
| start_time  | time    | not null                 |
| end_time    | time    | not null                 |
| remark      | string  | nullable                 |
| timestamps  |         |                          |

- Index: `section_id`, `room_id`
- Custom validation: `end_time > start_time`
- `room_id` is nullable for TBA rooms

### teachings

| Column     | Type         | Constraints               |
|------------|--------------|---------------------------|
| section_id | bigint       | not null, FK sections     |
| staff_id   | bigint       | not null, FK staffs       |
| load_ratio | decimal(3,2) | not null, default 1.0     |
| timestamps |              |                           |

- Unique index: `[section_id, staff_id]`
- Index: `staff_id`
- `load_ratio`: 0 < value <= 1
- Teaching is per **section**, not per time slot — a staff member teaches the whole section regardless of how many time slots it has

## Models

### Semester

```ruby
SEMESTER_NUMBERS = [1, 2, 3].freeze
SEMESTER_LABELS = { 1 => "First", 2 => "Second", 3 => "Summer" }.freeze

has_many :course_offerings, dependent: :destroy
has_many :courses, through: :course_offerings

validates :year_be, presence: true, numericality: { only_integer: true }
validates :semester_number, presence: true, inclusion: { in: SEMESTER_NUMBERS }
validates :year_be, uniqueness: { scope: :semester_number }

scope :ordered, -> { order(year_be: :desc, semester_number: :desc) }

def display_name
  "#{year_be}/#{semester_number}"
end
```

### Room

```ruby
ROOM_TYPES = %w[lecture lab seminar other].freeze
ROOM_TYPE_ICONS = {
  "lecture" => "class",
  "lab"     => "computer",
  "seminar" => "groups",
  "other"   => "room"
}.freeze

has_many :time_slots, dependent: :restrict_with_error

validates :building, presence: true
validates :room_number, presence: true, uniqueness: { scope: :building }
validates :room_type, inclusion: { in: ROOM_TYPES }, allow_nil: true
validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

def display_name
  "#{building}-#{room_number}"
end
```

### CourseOffering

```ruby
STATUSES = %w[planned confirmed cancelled].freeze
STATUS_ICONS = {
  "planned"   => "schedule",
  "confirmed" => "check_circle",
  "cancelled" => "cancel"
}.freeze

belongs_to :course
belongs_to :semester
has_many :sections, dependent: :destroy
has_many :time_slots, through: :sections
has_many :teachings, through: :sections

accepts_nested_attributes_for :sections, allow_destroy: true, reject_if: :all_blank

validates :status, presence: true, inclusion: { in: STATUSES }
validates :course_id, uniqueness: { scope: :semester_id,
  message: "is already offered in this semester" }
```

### Section

```ruby
belongs_to :course_offering
has_many :time_slots, dependent: :destroy
has_many :teachings, dependent: :destroy

accepts_nested_attributes_for :time_slots, allow_destroy: true, reject_if: :all_blank
accepts_nested_attributes_for :teachings, allow_destroy: true, reject_if: :all_blank

validates :section_number, presence: true,
  numericality: { only_integer: true, greater_than: 0 }
validates :section_number, uniqueness: { scope: :course_offering_id }
```

### TimeSlot

```ruby
DAYS_OF_WEEK = (0..6).to_a.freeze
DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
DAY_ABBRS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

belongs_to :section
belongs_to :room, optional: true

validates :day_of_week, presence: true, inclusion: { in: DAYS_OF_WEEK }
validates :start_time, presence: true
validates :end_time, presence: true
validate :end_time_after_start_time

def day_name = DAY_NAMES[day_of_week]
def day_abbr = DAY_ABBRS[day_of_week]
def time_range = "#{start_time.strftime('%H:%M')}-#{end_time.strftime('%H:%M')}"

private

def end_time_after_start_time
  return unless start_time && end_time
  errors.add(:end_time, "must be after start time") if end_time <= start_time
end
```

### Teaching

```ruby
belongs_to :section
belongs_to :staff

validates :load_ratio, presence: true,
  numericality: { greater_than: 0, less_than_or_equal_to: 1 }
validates :staff_id, uniqueness: { scope: :section_id }
```

### Changes to existing models

**Course** — add:
```ruby
has_many :course_offerings, dependent: :restrict_with_error
```

**Staff** — add:
```ruby
has_many :teachings, dependent: :restrict_with_error
has_many :sections, through: :teachings
# Also add `initials` column (string, unique) for scraper teacher matching
# See docs/schedule-scraper.md
```

**Grade** — add nullable FK to Section (for student timetable report, see `docs/schedule-reports.md`):
```ruby
belongs_to :section, optional: true
```
Migration adds `section_id` column (nullable, FK → sections). No backfill — existing grades remain null, resolved to first section (lowest `section_number`) at query time. The Grade importer will be updated to accept an optional section column.

## Routes

```ruby
resources :semesters do
  resources :course_offerings, only: [:index, :new, :create], shallow: true
end
resources :course_offerings, only: [:show, :edit, :update, :destroy]
resources :rooms
```

This gives us:
- `GET /semesters` — semester list
- `GET /semesters/:id` — semester detail (lists offerings)
- `GET /semesters/:semester_id/course_offerings/new` — add offering to semester
- `POST /semesters/:semester_id/course_offerings` — create
- `GET /course_offerings/:id` — offering detail (sections, time slots, teachings)
- `GET /course_offerings/:id/edit` — nested form
- `GET /rooms` — room directory

Sections, TimeSlots, and Teachings are **not** separate routes — they live inline on the CourseOffering form via `accepts_nested_attributes_for`.

## Controllers

All follow `docs/code-patterns.md` conventions.

### SemestersController

Standard CRUD. Show page lists all offerings for the semester.

### RoomsController

Inline add/edit on the index page (no separate show/new/edit pages). May evolve to full CRUD later if needed.

### CourseOfferingsController

- `new` and `create` are scoped to a semester (`before_action :set_semester`)
- `show`, `edit`, `update`, `destroy` are shallow (no semester in URL)
- Strong params accept nested section attributes (Phase 1), extended to time_slot and teaching attributes (Phase 2)

```ruby
def course_offering_params
  params.require(:course_offering).permit(
    :course_id, :status, :remark,
    sections_attributes: [:id, :section_number, :remark, :_destroy,
      time_slots_attributes: [:id, :day_of_week, :start_time, :end_time, :room_id, :remark, :_destroy],
      teachings_attributes: [:id, :staff_id, :load_ratio, :_destroy]
    ]
  )
end
```

## Views

### Semester index
DataTable with columns: Year (B.E.), Semester, # Offerings, Actions.

### Semester show
Header with semester label (e.g. "2568/1 — First Semester"). Table of course offerings:
- Columns: Course No, Course Name, Sections, Status, Actions
- "Add Course Offering" button for admins

### Room index (with inline editing)
DataTable with columns: Building, Room No, Type, Capacity, Actions.
Add/edit rows inline on the same page (no separate form pages). Simple reference data.

### CourseOffering show
Read-only display of the full nested structure:
- Course name + semester label in header
- For each section: section number, remark, then a table of time slots (Day, Time, Room, Staff with load ratios)

### CourseOffering form (nested)
- Top-level: course (Select2), status (select), remark (textarea)
- Nested fieldsets per section: section number, remark
  - Phase 2: nested rows per time slot (day select, start/end time, room Select2)
    - Phase 2: nested rows per teaching (staff Select2, load_ratio number input)
- "Add Section" / "Remove" buttons via Stimulus controller

## Sidebar Navigation

Add a **"Teaching"** section header (like the existing "Admin" header) between Grades and Users:

```haml
%li.mt-3.mb-1.px-3
  %small.text-uppercase.fw-semibold.text-body-secondary.letter-spacing-wide Teaching
%li.nav-item
  = link_to semesters_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'semesters'}" do
    = resource_icon("semesters")
    Semesters
%li.nav-item
  = link_to rooms_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'rooms'}" do
    = resource_icon("rooms")
    Rooms
```

Layer 3 (reports) will add more items under this section header later.

Add to `ApplicationHelper::RESOURCE_ICONS`:
```ruby
"semesters"        => "calendar_month",
"course_offerings" => "event_note",
"rooms"            => "meeting_room",
```

## Stimulus: nested_fields_controller.js

New generic controller for dynamic add/remove of `accepts_nested_attributes_for` field groups.

**Pattern**: A `<template>` element holds the HTML for one nested row. The controller clones it on "Add", replacing a `NEW_RECORD` placeholder in all `name` attributes with a unique timestamp index. "Remove" toggles a `_destroy` hidden field and hides the row.

This controller is reusable for any nested form in the app going forward.

## CSV Import

### Overview

A single `ScheduleImporter` handles the flat denormalized format that universities typically export. One row = one time slot, with course/section/staff repeated. The importer creates or finds the nested records (Semester, CourseOffering, Section, TimeSlot, Teaching) from each row.

Follows the existing importer pattern: subclass of `Importers::Base`, registered in `DataImport::IMPORTERS`.

### Expected file format

| course_no | revision_year | section | day | start_time | end_time | building | room_number | instructor | load_ratio |
|-----------|---------------|---------|-----|------------|----------|----------|-------------|------------|------------|
| 2110101   | 2567          | 1       | Mon | 9:00       | 10:30    | ENG4     | 303         | Smith      | 1.0        |
| 2110101   | 1             | Wed     | 9:00       | 10:30    | ENG4     | 303         | Smith      | 1.0        |
| 2110101   | 2567          | 2       | Tue | 13:00      | 14:30    | ENG4     | 305         | Jones      | 0.5        |

The exact column names will vary — aliases and auto-map handle that.

### Attribute definitions

| Attribute      | Required | Notes |
|----------------|----------|-------|
| course_no      | yes      | Lookup existing Course |
| revision_year  | no       | For course lookup; if blank, use latest revision |
| section_number | yes      | Integer, may be non-sequential (1, 5, 99) |
| day            | yes      | Accepts: Mon/Monday/จันทร์/1, etc. |
| start_time     | yes      | HH:MM format |
| end_time       | yes      | HH:MM format |
| building       | no       | Find-or-create Room if both building+room_number present |
| room_number    | no       | Paired with building |
| instructor     | no       | Lookup Staff by name; skip teaching record if blank |
| load_ratio     | no       | Default 1.0 |
| remark         | no       | Applied to section |

**Fixed-value fields** (set via constant on the mapping page, not per-row):
- **Semester** — user picks the target semester from a dropdown. All rows import into this semester.

### Processing logic

For each row:
1. **Course**: find by `course_no` (+ `revision_year` if given, else latest). Error if not found.
2. **Semester**: from the fixed-value constant (selected on mapping page).
3. **CourseOffering**: find-or-create by course + semester. Default status `"planned"`.
4. **Section**: find-or-create by course_offering + section_number.
5. **Room**: if building + room_number present, find-or-create Room. Otherwise nil.
6. **TimeSlot**: find-or-create by section + day_of_week + start_time + end_time. Attach room.
7. **Teaching**: if instructor present, find Staff by name match. Find-or-create Teaching by section + staff. Set load_ratio.

Find-or-create avoids duplicates when multiple rows share the same course/section/room.

### Staff name matching

Instructor lookup tries in order:
1. Exact match on `display_name` (academic_title + full_name)
2. Exact match on `full_name`
3. Exact match on `full_name_th`
4. Partial match (last_name contains)
5. If no match → log warning in row_errors, skip teaching record (don't fail the row)

### Registration

Add to `DataImport::IMPORTERS`:
```ruby
"Schedule" => "Importers::ScheduleImporter"
```

### Mode

Only **upsert** makes sense — re-importing the same semester's schedule should update existing records, not create duplicates. The `unique_key_fields` concept doesn't map cleanly to a single model, so the importer uses find-or-create logic internally rather than the base class's upsert flow.

## Web Scraper

Separate design doc: `docs/schedule-scraper.md`. Pluggable scraper system with two backends (CuGetReg GraphQL API + CAS Reg HTML scraping), rate limiting, rake task, console helpers.

## Implementation Phases

### Phase 1: Foundation
- Migrations + models + fixtures + model tests for **all 6 tables**
- CRUD controllers + views for **Semester** and **Room**
- CourseOffering controller with **Section nested form only** (no time slots/teachings yet)
- Routes, sidebar nav, resource icons

### Phase 2: Time Slots + Teachings
- Extend CourseOffering form with **TimeSlot and Teaching** nested fields
- `nested_fields_controller.js` Stimulus controller
- System tests for the full nested form

### Phase 3: CSV Import
- `Importers::ScheduleImporter` following existing importer pattern
- Register in `DataImport::IMPORTERS`
- Staff name matching logic
- Model + system tests for import flow

### Phase 4: Embedded sections (Layer 2)
- **Staff show page**: "Teaching" section — semester dropdown, table of their time slots + courses + load ratios
- **Course show page**: "Offerings" section — table of semesters where the course was offered, with section count and status
- **Student show page**: "Schedule" section — semester dropdown, table of enrolled courses with time slots (requires linking grades/enrollments to course offerings)

### Phase 5: Web Scraper
Separate design doc: `docs/schedule-scraper.md`. Covers:
- Staff `initials` column migration
- Section `enrollment_current`/`enrollment_max` columns migration
- Scraper base class + CuGetReg backend (GraphQL)
- Scraper job, controller, UI
- CAS Reg backend (HTML parsing, fallback)
- Rate limiting config (`config/scraper.yml`)

### Phase 6: Reports (Layer 3)
Separate design doc: `docs/schedule-reports.md`. Covers:
- Room + semester → week calendar
- Staff + semester → week calendar + workload summary
- Set of courses + semester → curriculum week calendar
- Student + semester → week calendar with grades
- Conflict detection (room/staff double-booking)

## Testing

Run: `bin/rails test` (model/controller), `bin/rails test:system` (system), `AUTO_LOGIN=1 bin/dev` (manual).

### Fixtures

```yaml
# semesters.yml
sem_2568_1:
  year_be: 2568
  semester_number: 1

sem_2568_2:
  year_be: 2568
  semester_number: 2

# rooms.yml
eng4_303:
  building: ENG4
  room_number: "303"
  room_type: lecture
  capacity: 60

eng4_lab1:
  building: ENG4
  room_number: LAB1
  room_type: lab
  capacity: 40

# course_offerings.yml — references course + semester fixtures
# sections.yml — references course_offering fixtures
# time_slots.yml — references section + room fixtures
# teachings.yml — references section + staff fixtures
```

A `staffs.yml` fixture file is also needed (does not currently exist).

### Model tests

**Semester** (`test/models/semester_test.rb`)
- valid with year_be + semester_number
- requires year_be
- requires semester_number
- semester_number must be 1, 2, or 3
- unique on [year_be, semester_number]
- `display_name` returns "2568/1"
- `ordered` scope sorts desc by year then semester

**Room** (`test/models/room_test.rb`)
- valid with building + room_number
- requires building
- requires room_number
- unique on [building, room_number]
- room_type must be in ROOM_TYPES (when present)
- capacity must be positive integer (when present)
- `display_name` returns "ENG4-303"
- cannot delete room with associated time slots (`restrict_with_error`)

**CourseOffering** (`test/models/course_offering_test.rb`)
- valid with course + semester + status
- requires course
- requires semester
- status defaults to "planned"
- status must be in STATUSES
- unique on [course_id, semester_id]
- destroys sections on delete (cascade)

**Section** (`test/models/section_test.rb`)
- valid with course_offering + section_number
- requires section_number
- section_number must be positive integer
- unique on [course_offering_id, section_number]
- destroys time_slots and teachings on delete (cascade)

**TimeSlot** (`test/models/time_slot_test.rb`)
- valid with section + day_of_week + start_time + end_time
- requires day_of_week, start_time, end_time
- day_of_week must be 0-6
- room is optional
- end_time must be after start_time
- `day_name` returns "Monday" for day_of_week=1
- `time_range` returns "09:00-10:30"

**Teaching** (`test/models/teaching_test.rb`)
- valid with section + staff + load_ratio
- requires load_ratio
- load_ratio must be > 0 and <= 1
- unique on [section_id, staff_id]
- cannot delete staff with associated teachings (`restrict_with_error`)

### Controller tests

**SemestersController** (`test/controllers/semesters_controller_test.rb`)
- non-admin cannot create semester
- non-admin cannot update semester
- non-admin cannot delete semester

**RoomsController** (`test/controllers/rooms_controller_test.rb`)
- non-admin cannot create room
- non-admin cannot update room
- non-admin cannot delete room

**CourseOfferingsController** (`test/controllers/course_offerings_controller_test.rb`)
- non-admin cannot create offering
- non-admin cannot update offering
- non-admin cannot delete offering

### System tests

**Semesters** (`test/system/semesters_test.rb`)
- index shows semesters
- admin can create semester
- admin can edit semester
- admin can delete semester
- show page lists course offerings

**Rooms** (`test/system/rooms_test.rb`)
- index shows rooms
- admin can add room inline
- admin can edit room inline
- admin can delete room

**CourseOfferings** (`test/system/course_offerings_test.rb`)
- admin can create offering with sections (Phase 1)
- admin can add/remove sections dynamically (Phase 1)
- show page displays sections with time slots and staff (Phase 2)
- admin can add time slots and teachings to sections (Phase 2)
- non-admin sees read-only views

## Implementation Steps

Concrete steps for building this feature across multiple Claude Code instances. Steps marked **(parallel)** can run simultaneously in separate terminals.

### Step 1: Foundation — models, routes, sidebar
Single instance. All shared infrastructure that everything else depends on.
- All 6 migrations (semesters, rooms, course_offerings, sections, time_slots, teachings)
- Migrations for existing tables: `section_id` on grades, `initials` on staffs, `description`/`description_th` on courses, `enrollment_current`/`enrollment_max` on sections
- All 6 new models + updates to Course, Staff, Grade
- All fixture files (including `staffs.yml` if missing)
- All model tests
- Routes (`semesters`, `rooms`, shallow `course_offerings`, `scrapes`)
- Sidebar "Teaching" section + entries
- `RESOURCE_ICONS` entries

### Step 2: Semester CRUD + Room CRUD **(parallel)**
Two instances, separate files.
- **Instance A**: `SemestersController` + views (index, show, new, edit, form) + controller tests + system tests
- **Instance B**: `RoomsController` + views (inline add/edit on index) + controller tests + system tests

### Step 3: CourseOffering CRUD with nested Section form
Single instance. Depends on Step 2 (Semester views).
- `CourseOfferingsController` (shallow nested under semesters)
- Views: index (on semester show), show, new, edit, form with nested section fields
- Controller tests + system tests

### Step 4: CSV Import + CuGetReg scraper **(parallel)**
Two instances, completely separate service classes.
- **Instance A**: `Importers::ScheduleImporter` + register in `DataImport::IMPORTERS` + tests
- **Instance B**: `Scrapers::Base` + `Scrapers::CuGetReg` + `config/scraper.yml` + console helpers + fixture files + tests

### Step 5: Nested form Phase 2 + CAS Reg scraper **(parallel)**
Two instances.
- **Instance A**: Extend CourseOffering form with TimeSlot + Teaching nested fields + `nested_fields_controller.js` + system tests
- **Instance B**: `Scrapers::CasReg` + rake task (`scraper:run`) + scraper web UI (`ScrapesController` + views) + tests

### Step 6: Embedded sections (Layer 2)
Single instance.
- Staff show page: "Teaching" section
- Course show page: "Offerings" section
- Student show page: "Schedule" section

### Step 7: Reports (Layer 3)
Per `docs/schedule-reports.md`. Can be split across instances by report.
