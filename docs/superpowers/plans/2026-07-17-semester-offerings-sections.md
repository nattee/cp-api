# Semester Offerings Table: Per-Section Detail, Scope Filter, CSV Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the `semesters/show` offerings table with one line per section (teachers, schedule, enrollment), add a `course_scope=dept|all` filter (default `dept`), and add a per-section CSV export that honors the scope.

**Architecture:** Formatting logic lives in a new `CourseOfferingsHelper` (plain-text methods) shared by the HAML view and a new `Exporters::SemesterSectionsExporter` so table and CSV cannot drift. The controller parses the scope param with the exact Teaching Matrix logic and eager-loads the section tree. Spec: `docs/superpowers/specs/2026-07-17-semester-offerings-sections-design.md`.

**Tech Stack:** Rails 8.1, HAML, Minitest + fixtures, Capybara system tests, Mercurial.

## Global Constraints

- **Version control is Mercurial**: `hg add <file>` / `hg commit <explicit files> -m "..."` — always name explicit files (repo may have unrelated dirty changes). Commit messages lead with WHY (first paragraph = motivation), then what.
- **Scope parsing verbatim from teaching_matrix**: `params[:course_scope] == "all" ? "all" : "dept"`; dept = `courses.course_no LIKE '2110%'`.
- **Staff short-name rule**: `initials.presence || display_name_th` (same as courses/show Teachers column).
- **Tests are deferred** (project convention: ask the user after the feature works). Task 4 runs ONLY after the user confirms they want tests now.
- Views are HAML; intranet-only (no CDN/external URLs); muted separators so values stay visually primary.
- Fixture facts used throughout: `sem_2568_1` has `intro_computing_2568_1` (2110101, confirmed; sec 1: Mon+Wed 09:00–10:30 ENG4-303, teacher JS; sec 2: Tue 13:00–14:30 ENG4-LAB1, teachers JJ+JS) and `senior_project_2568_1` (2110499, planned; sec 1 has no slots/teachings). `sem_2567_1` has 2110101 (secs 1, 33) plus non-dept `2103106`.

---

### Task 1: Section formatting helper

**Files:**
- Create: `app/helpers/course_offerings_helper.rb`

**Interfaces:**
- Consumes: `TimeSlot#day_abbr`, `TimeSlot#time_range` ("HH:MM-HH:MM"), `Room#display_name` ("ENG4-303"), `Staff#initials` / `#display_name_th`, `Section#enrollment_current` / `#enrollment_max`.
- Produces (used by Tasks 2 and 3):
  - `staff_short_name(staff) → String`
  - `section_schedule_summary(section) → String | nil` (plain text)
  - `section_enrollment_summary(section) → String | nil` (plain text)

- [ ] **Step 1: Create the helper**

```ruby
# app/helpers/course_offerings_helper.rb
module CourseOfferingsHelper
  # Registrar-style short name for teacher lists: 3-letter initials when
  # assigned, Thai display name otherwise (same rule as courses/show).
  def staff_short_name(staff)
    staff.initials.presence || staff.display_name_th
  end

  # Plain-text weekly schedule for a section. Slots sharing the same time and
  # room collapse into one segment ("Mon/Wed 09:00-10:30 ENG4-303"); distinct
  # segments join with "; "; roomless slots render "TBA". Returns nil when the
  # section has no time slots. Plain text so the CSV exporter reuses it verbatim.
  def section_schedule_summary(section)
    slots = section.time_slots.sort_by { |ts| [ts.day_of_week, ts.start_time] }
    return nil if slots.empty?

    slots.group_by { |ts| [ts.start_time, ts.end_time, ts.room&.display_name] }
         .map do |(_, _, room_name), group|
           "#{group.map(&:day_abbr).join('/')} #{group.first.time_range} #{room_name || 'TBA'}"
         end
         .join("; ")
  end

  # "45/50" enrollment summary; "?" stands in for a missing side; nil when
  # both sides are missing.
  def section_enrollment_summary(section)
    return nil if section.enrollment_current.nil? && section.enrollment_max.nil?
    "#{section.enrollment_current || '?'}/#{section.enrollment_max || '?'}"
  end
end
```

Notes for the implementer:
- Group by `room&.display_name` (not `room_id`) so unsaved in-memory records used in unit tests group correctly.
- `sort_by` + `group_by` (not `.order`) — sections/slots arrive eager-loaded; SQL ordering would re-query per section.

- [ ] **Step 2: Verify with in-memory objects (no DB rows needed)**

Run:
```bash
bin/rails runner '
include CourseOfferingsHelper
s = Section.new(section_number: 1)
s.time_slots.build(day_of_week: 1, start_time: "09:00", end_time: "10:30", room: Room.new(building: "ENG4", room_number: "303"))
s.time_slots.build(day_of_week: 3, start_time: "09:00", end_time: "10:30", room: Room.new(building: "ENG4", room_number: "303"))
s.time_slots.build(day_of_week: 5, start_time: "13:00", end_time: "15:00")
puts section_schedule_summary(s)
puts section_enrollment_summary(Section.new(enrollment_current: 45)).inspect
puts section_enrollment_summary(Section.new).inspect
'
```
Expected output:
```
Mon/Wed 09:00-10:30 ENG4-303; Fri 13:00-15:00 TBA
"45/?"
nil
```
(The two ENG4-303 Room instances group because the key is the display-name string.)

- [ ] **Step 3: Commit**

```bash
hg add app/helpers/course_offerings_helper.rb
hg commit app/helpers/course_offerings_helper.rb -m "Add section formatting helper for offerings table and CSV export

The semester offerings table and its upcoming per-section CSV export both
need the same teacher/schedule/enrollment text; building it in one helper
keeps the two from drifting (spec 2026-07-17-semester-offerings-sections).

- staff_short_name: initials with Thai-name fallback (courses/show rule)
- section_schedule_summary: slots collapsed by identical time+room
- section_enrollment_summary: current/max with ? for a missing side"
```

---

### Task 2: Per-section CSV exporter + route + controller action

**Files:**
- Create: `app/services/exporters/semester_sections_exporter.rb`
- Modify: `app/controllers/semesters_controller.rb` (before_action list, new action, new private method)
- Modify: `config/routes.rb` (semesters member block, currently `get :export` only)

**Interfaces:**
- Consumes: Task 1's `staff_short_name`, `section_schedule_summary`; `Exporters::Base` (`HEADERS` const + private `rows`, public `to_csv`/`filename`, `byte_order_mark?` hook).
- Produces: `Exporters::SemesterSectionsExporter.new(semester, course_scope: "dept"|"all")` with `#to_csv` and `#filename`; route helper `export_sections_semester_path(semester, course_scope: ...)`; controller private `course_scope_param → "dept"|"all"` (reused by Task 3).

- [ ] **Step 1: Create the exporter**

```ruby
# app/services/exporters/semester_sections_exporter.rb
module Exporters
  # Human-facing listing of a semester's offerings, one row per section
  # (plus one blank-section row per offering that has no sections, so the
  # export is always a complete offering list). Unlike ScheduleExporter this
  # does NOT round-trip through an importer — it mirrors the semesters/show
  # table, including its course_scope filter.
  class SemesterSectionsExporter < Base
    include CourseOfferingsHelper

    HEADERS = %w[course_no course_name section teachers schedule enrolled max status].freeze

    attr_reader :semester, :course_scope

    def initialize(semester, course_scope: "dept")
      @semester = semester
      @course_scope = course_scope
    end

    def filename
      suffix = course_scope == "dept" ? "_dept" : ""
      "sections_#{semester.year_be}_#{semester.semester_number}#{suffix}.csv"
    end

    private

    # Teacher names fall back to Thai; BOM makes Excel read the file as UTF-8.
    # Safe here because this CSV never feeds an importer.
    def byte_order_mark?
      true
    end

    def rows
      offerings = semester.course_offerings.joins(:course)
      offerings = offerings.where("courses.course_no LIKE ?", "2110%") if course_scope == "dept"
      offerings = offerings.order("courses.course_no")
                           .includes(:course, sections: [{ teachings: :staff }, { time_slots: :room }])

      offerings.flat_map do |offering|
        course = offering.course
        if offering.sections.any?
          offering.sections.sort_by(&:section_number).map do |section|
            [course.course_no, course.name, section.section_number,
             section.teachings.map { |t| staff_short_name(t.staff) }.join(", "),
             section_schedule_summary(section),
             section.enrollment_current, section.enrollment_max,
             offering.status]
          end
        else
          [[course.course_no, course.name, nil, nil, nil, nil, nil, offering.status]]
        end
      end
    end
  end
end
```

- [ ] **Step 2: Add the route**

In `config/routes.rb`, the semesters member block becomes:

```ruby
  resources :semesters do
    member do
      get :export
      get :export_sections
    end
    resources :course_offerings, only: [:index, :new, :create], shallow: true
  end
```

- [ ] **Step 3: Add the controller action**

In `app/controllers/semesters_controller.rb`:

1. Extend the before_action:
```ruby
  before_action :set_semester, only: %i[show edit update destroy export export_sections]
```
2. Add the action after the existing `export` action:
```ruby
  def export_sections
    exporter = Exporters::SemesterSectionsExporter.new(@semester, course_scope: course_scope_param)
    send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
  end
```
3. Add the private method (below `set_semester`); Task 3's `show` reuses it:
```ruby
  # Same parse rule as SchedulesController#teaching_matrix: anything but an
  # explicit "all" means the department default.
  def course_scope_param
    params[:course_scope] == "all" ? "all" : "dept"
  end
```

- [ ] **Step 4: Verify against the dev database**

Run:
```bash
bin/rails runner '
sem = Semester.order(year_be: :desc, semester_number: :desc).first
e = Exporters::SemesterSectionsExporter.new(sem, course_scope: "dept")
puts e.filename
puts e.to_csv.lines.first(5).join
puts "all rows: #{Exporters::SemesterSectionsExporter.new(sem, course_scope: "all").to_csv.lines.size - 1}"
'
```
Expected: filename like `sections_2569_2_dept.csv`; a header row `course_no,course_name,...` (first line starts with the UTF-8 BOM — invisible in most terminals); data rows with only `2110*` course numbers; the `all` row count ≥ the dept count. Also confirm the route exists:
```bash
bin/rails runner 'puts Rails.application.routes.url_helpers.export_sections_semester_path(1, course_scope: "all")'
```
Expected: `/semesters/1/export_sections?course_scope=all`

- [ ] **Step 5: Commit**

```bash
hg add app/services/exporters/semester_sections_exporter.rb
hg commit app/services/exporters/semester_sections_exporter.rb app/controllers/semesters_controller.rb config/routes.rb -m "Add per-section CSV export for a semester's offerings

The only semester export was the schedule import round-trip format (one
row per time slot, no enrollment or status), which is not usable as a
term listing in a spreadsheet. This adds a human-facing export: one row
per section with teachers, schedule, and enrollment, plus a blank-section
row for offerings without sections so the offering list stays complete
(spec 2026-07-17-semester-offerings-sections).

- Exporters::SemesterSectionsExporter, sharing CourseOfferingsHelper text
  with the semesters/show table so the two cannot drift
- course_scope dept|all (teaching_matrix semantics), UTF-8 BOM for Thai
  teacher names in Excel
- GET /semesters/:id/export_sections"
```

---

### Task 3: Show page — scoped query, per-section table, toggle, buttons, cross-links

**Files:**
- Modify: `app/controllers/semesters_controller.rb:9-11` (the `show` action)
- Modify: `app/views/semesters/show.html.haml` (whole file shown below)
- Modify: `docs/backlog.md` (item 1 seed list)

**Interfaces:**
- Consumes: Task 1's `staff_short_name` / `section_schedule_summary` / `section_enrollment_summary`; Task 2's `course_scope_param` and `export_sections_semester_path`; existing `schedules_teaching_matrix_path(year:, semester_number:)` and `schedules_conflicts_path(semester_id:)` (conflicts runs whenever `semester_id` is present — no run param).
- Produces: `@course_scope` assign used inside the view.

- [ ] **Step 1: Scope + eager-load in the show action**

Replace the current `show` (`@course_offerings = @semester.course_offerings.includes(:course, :sections)`) with:

```ruby
  def show
    @course_scope = course_scope_param
    offerings = @semester.course_offerings
    offerings = offerings.joins(:course).where("courses.course_no LIKE ?", "2110%") if @course_scope == "dept"
    @course_offerings = offerings.includes(:course, sections: [{ teachings: :staff }, { time_slots: :room }])
  end
```

- [ ] **Step 2: Rewrite the view**

Replace the full contents of `app/views/semesters/show.html.haml` with:

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1
    = @semester.display_name
    %small.text-muted= "— #{Semester::SEMESTER_LABELS[@semester.semester_number]} Semester"
  .d-flex.gap-2
    = link_to export_semester_path(@semester, course_scope: @course_scope), class: "btn btn-outline-secondary" do
      %span.material-symbols{style: "font-size: 16px; vertical-align: middle"} download
      Export Schedule
    = link_to export_sections_semester_path(@semester, course_scope: @course_scope), class: "btn btn-outline-secondary" do
      %span.material-symbols{style: "font-size: 16px; vertical-align: middle"} download
      Export Sections
    - if current_user.admin?
      = link_to "Edit", edit_semester_path(@semester), class: "btn btn-outline-secondary"
    = link_to "Back", semesters_path, class: "btn btn-outline-primary"

.card{"data-controller" => "datatable"}
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon("course_offerings")
        Course Offerings
        %span.text-muted.ms-2.fw-normal
          (#{@course_offerings.size})
      .d-flex.gap-2.align-items-center
        .btn-group.course-scope-toggle
          = link_to "Dept (2110)", semester_path(@semester, course_scope: "dept"), class: "btn btn-sm btn-outline-secondary #{'active' if @course_scope == 'dept'}"
          = link_to "All", semester_path(@semester, course_scope: "all"), class: "btn btn-sm btn-outline-secondary #{'active' if @course_scope == 'all'}"
        - if current_user.admin?
          = link_to "Add Course Offering", new_semester_course_offering_path(@semester), class: "btn btn-primary btn-sm"
    %p.text-muted.small.mb-2
      = link_to "Department-wide teaching matrix for #{@semester.display_name} →", schedules_teaching_matrix_path(year: @semester.year_be, semester_number: @semester.semester_number)
      %span.mx-1 ·
      = link_to "Room & staff double-bookings →", schedules_conflicts_path(semester_id: @semester.id)
    .table-responsive
      %table.table.table-hover.mb-0{"data-datatable-target" => "table"}
        %thead
          %tr
            %th Course No
            %th Course Name
            %th Sections
            %th Status
            %th Actions
        %tbody
          - @course_offerings.each do |offering|
            %tr
              %td= offering.course.course_no
              %td= offering.course.name
              %td
                - if offering.sections.any?
                  - offering.sections.sort_by(&:section_number).each do |section|
                    %div
                      = "Sec #{section.section_number}"
                      - if section.teachings.any?
                        %span.text-muted ·
                        = safe_join(section.teachings.map { |t| link_to(staff_short_name(t.staff), staff_path(t.staff)) }, ", ")
                      - if (schedule = section_schedule_summary(section))
                        %span.text-muted ·
                        = schedule
                      - if (enrollment = section_enrollment_summary(section))
                        %span.text-muted ·
                        = enrollment
                - else
                  %span.text-muted No sections
              %td
                %span.badge{class: "badge-#{offering.status.dasherize}"}= offering.status.titleize
              %td
                = link_to course_offering_path(offering), class: "btn-ghost btn-ghost-primary me-1", title: "Show" do
                  %span.material-symbols{style: "font-size: 18px"} visibility
                - if current_user.admin?
                  = link_to edit_course_offering_path(offering), class: "btn-ghost btn-ghost-secondary me-1", title: "Edit" do
                    %span.material-symbols{style: "font-size: 18px"} edit
                  = link_to course_offering_path(offering), data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "btn-ghost btn-ghost-danger", title: "Delete" do
                    %span.material-symbols{style: "font-size: 18px"} delete
```

What changed vs the old file (everything else is verbatim): two export buttons (relabel + new), `course_scope` carried on both; scope toggle btn-group (class `course-scope-toggle` for system-test targeting); cross-link line to Teaching Matrix and Conflicts; the Sections cell (was `offering.sections.size`) now renders one `%div` per section; the sections-count column header stays "Sections".

- [ ] **Step 3: Extend the backlog seed list**

In `docs/backlog.md`, append to the item-1 seed list (after the staffs/show → teaching_matrix bullet):

```markdown
- **semesters/show** → `/schedules/teaching_matrix` (year + semester_number
  pre-filled) and `/schedules/conflicts` (semester_id pre-filled): the
  dept-wide who-teaches-what and double-booking views for the term shown on
  the page. Links added 2026-07-17.
```

- [ ] **Step 4: Verify in the browser and screenshot for user review**

```bash
AUTO_LOGIN=1 bin/rails server -p 3000 &
sleep 5
SEM_ID=$(bin/rails runner 'puts Semester.order(year_be: :desc, semester_number: :desc).first.id')
firefox --headless --window-size=1600,1200 --screenshot /tmp/claude-1002/-home-dae-cp-api/587dd2dd-1db1-49d6-b781-3d5b88829828/scratchpad/semester_dept.png "http://localhost:3000/semesters/$SEM_ID"
firefox --headless --window-size=1600,1200 --screenshot /tmp/claude-1002/-home-dae-cp-api/587dd2dd-1db1-49d6-b781-3d5b88829828/scratchpad/semester_all.png "http://localhost:3000/semesters/$SEM_ID?course_scope=all"
```

Check: section lines render with muted `·` separators; dept view shows only 2110 courses and the count shrinks accordingly; toggle active state follows the URL; both export buttons and both cross-links present. **Show both screenshots to the user and get approval before committing** (standing preference: UI changes are approved from rendered output). Then kill the server.

- [ ] **Step 5: Commit**

```bash
hg commit app/controllers/semesters_controller.rb app/views/semesters/show.html.haml docs/backlog.md -m "Show per-section detail and a dept-course filter on the semester page

The offerings table only showed a section count, so who teaches each
section, when/where it meets, and how full it is required clicking into
every offering; the term list was also un-narrowable to department
courses (spec 2026-07-17-semester-offerings-sections).

- Sections column: one line per section (Sec N, teachers as initials
  links, collapsed time+room schedule, enrolled/max)
- course_scope dept|all toggle, default dept (teaching_matrix semantics);
  count and both export links follow the scope
- relabel round-trip export to Export Schedule, next to Export Sections
- backlog item 1 applied: pre-filled cross-links to Teaching Matrix and
  Conflicts for the term"
```

---

### Task 4: Tests — GATED: run only after the user confirms

Ask the user first (project convention). If they defer, stop here.

**Files:**
- Create: `test/helpers/course_offerings_helper_test.rb`
- Create: `test/services/exporters/semester_sections_exporter_test.rb`
- Modify: `test/system/semesters_test.rb` (append tests inside the class)

**Interfaces:**
- Consumes: Tasks 1–3 code; fixtures listed in Global Constraints; `Exporters::Base::BOM` (exports start with a BOM — strip before `CSV.parse` or header matching fails).

- [ ] **Step 1: Helper unit tests**

```ruby
# test/helpers/course_offerings_helper_test.rb
require "test_helper"

class CourseOfferingsHelperTest < ActionView::TestCase
  test "staff_short_name prefers initials, falls back to Thai display name" do
    assert_equal "JS", staff_short_name(staffs(:lecturer_smith))
    staff = Staff.new(first_name: "Anon", last_name: "Ymous",
                      first_name_th: "อานนท์", last_name_th: "ไอมัส", academic_title: "อ.")
    assert_equal "อ.อานนท์ ไอมัส", staff_short_name(staff)
  end

  test "section_schedule_summary collapses same time and room across days" do
    assert_equal "Mon/Wed 09:00-10:30 ENG4-303", section_schedule_summary(sections(:intro_sec_1))
  end

  test "section_schedule_summary splits differing rooms and renders TBA" do
    section = Section.new(section_number: 9)
    section.time_slots.build(day_of_week: 1, start_time: "09:00", end_time: "10:30", room: rooms(:eng4_303))
    section.time_slots.build(day_of_week: 3, start_time: "09:00", end_time: "10:30")
    assert_equal "Mon 09:00-10:30 ENG4-303; Wed 09:00-10:30 TBA", section_schedule_summary(section)
  end

  test "section_schedule_summary is nil without slots" do
    assert_nil section_schedule_summary(sections(:senior_sec_1))
  end

  test "section_enrollment_summary handles full, partial, and missing data" do
    assert_equal "45/50", section_enrollment_summary(Section.new(enrollment_current: 45, enrollment_max: 50))
    assert_equal "45/?", section_enrollment_summary(Section.new(enrollment_current: 45))
    assert_equal "?/50", section_enrollment_summary(Section.new(enrollment_max: 50))
    assert_nil section_enrollment_summary(Section.new)
  end
end
```

- [ ] **Step 2: Exporter tests**

```ruby
# test/services/exporters/semester_sections_exporter_test.rb
require "test_helper"
require "csv"

class Exporters::SemesterSectionsExporterTest < ActiveSupport::TestCase
  # Exports carry a UTF-8 BOM (Thai teacher names in Excel); strip it before
  # parsing or the first header comes back as "﻿course_no".
  def parse(exporter)
    CSV.parse(exporter.to_csv.delete_prefix(Exporters::Base::BOM), headers: true)
  end

  test "one row per section with expected headers" do
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)))

    # intro_computing_2568_1 has sections 1+2, senior_project_2568_1 has section 1
    assert_equal 3, csv.size
    assert_equal %w[course_no course_name section teachers schedule enrolled max status], csv.headers
  end

  test "section row carries teachers, schedule, and status" do
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)))
    row = csv.find { |r| r["course_no"] == "2110101" && r["section"] == "1" }

    assert_equal "JS", row["teachers"]
    assert_equal "Mon/Wed 09:00-10:30 ENG4-303", row["schedule"]
    assert_equal "confirmed", row["status"]
  end

  test "dept scope filters to 2110 courses; all includes everything" do
    dept = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2567_1), course_scope: "dept"))
    all = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2567_1), course_scope: "all"))

    assert_equal %w[2110101 2110101], dept["course_no"]
    assert_includes all["course_no"], "2103106"
    assert_equal 3, all.size
  end

  test "offering without sections emits one blank-section row" do
    CourseOffering.create!(course: courses(:gened_course), semester: semesters(:sem_2568_2), status: "planned")
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_2), course_scope: "all"))
    row = csv.find { |r| r["course_no"] == "2103106" }

    assert_nil row["section"]
    assert_equal "planned", row["status"]
  end

  test "filename carries the scope suffix" do
    assert_equal "sections_2568_1_dept.csv", Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)).filename
    assert_equal "sections_2568_1.csv", Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1), course_scope: "all").filename
  end
end
```

- [ ] **Step 3: Run unit tests**

Run: `bin/rails test test/helpers/course_offerings_helper_test.rb test/services/exporters/semester_sections_exporter_test.rb`
Expected: all green, 0 failures.

- [ ] **Step 4: System tests**

Append inside the existing class in `test/system/semesters_test.rb`:

```ruby
  test "semester page shows per-section detail with exports and report links" do
    visit semester_path(semesters(:sem_2568_1))

    assert_text "Sec 1"
    assert_text "JS"
    assert_text "Mon/Wed 09:00-10:30 ENG4-303"
    assert_link "Export Schedule"
    assert_link "Export Sections"
    assert_link "Department-wide teaching matrix for 2568/1 →"
    assert_link "Room & staff double-bookings →"
  end

  test "course scope toggle hides and shows non-department courses" do
    visit semester_path(semesters(:sem_2567_1))
    assert_text "2110101"
    assert_no_text "2103106" # default scope is dept

    within(".course-scope-toggle") { click_on "All" }
    assert_text "2103106"

    within(".course-scope-toggle") { click_on "Dept (2110)" }
    assert_no_text "2103106"
  end
```

Note: do not assert the "No sections" placeholder here — every fixture offering has at least one section (`senior_project_2568_1`'s section merely lacks slots/teachings), so that state has no fixture coverage; the exporter test's blank-row case covers the zero-section path instead.

- [ ] **Step 5: Run system tests**

Run: `bin/rails test:system test/system/semesters_test.rb`
Expected: all green (headless Firefox), 0 failures.

- [ ] **Step 6: Run the full suite to catch regressions**

Run: `bin/rails test`
Expected: 0 failures (the schedule exporter and schedules system tests exercise neighboring code).

- [ ] **Step 7: Commit**

```bash
hg add test/helpers/course_offerings_helper_test.rb test/services/exporters/semester_sections_exporter_test.rb
hg commit test/helpers/course_offerings_helper_test.rb test/services/exporters/semester_sections_exporter_test.rb test/system/semesters_test.rb -m "Test per-section offerings table, scope filter, and sections export

Locks in the behaviors the semester page rework introduced: slot
collapsing and TBA/enrollment fallbacks in the shared helper, per-section
CSV rows (incl. the blank row for section-less offerings and the BOM),
dept-default scope filtering, and the page-level toggle."
```
