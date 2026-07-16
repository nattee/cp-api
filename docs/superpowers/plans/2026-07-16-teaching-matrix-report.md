# Teaching Matrix Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a staff × course section-count matrix report at `/schedules/teaching_matrix` and retire the `Reports::CourseTeachers` web report it absorbs (net web-report count stays flat).

**Architecture:** A 7th read-only action in `SchedulesController` (sibling of `workload`), one `Teaching` join query pivoted in Ruby, rendered as a plain HAML matrix reusing the staff-page `.teaching-history-table` styling. Bundled: a Teachers column on courses/show Offerings (the retirement blocker named in `docs/backlog.md` item 2), then deletion of `Reports::CourseTeachers`.

**Tech Stack:** Rails 8.1, HAML, Minitest fixtures, Mercurial (hg — NOT git).

**Spec:** `docs/superpowers/specs/2026-07-16-teaching-matrix-report-design.md`

## Global Constraints

- **Version control is Mercurial.** `hg add`/`hg rm`/`hg commit` — never git. Commit messages MUST lead with WHY (first paragraph = motivation), then what. Always name explicit files on `hg commit` (the repo may have unrelated dirty files).
- **Year fields are Buddhist Era.** Every year label in the UI must say the era: "Year (B.E.)".
- **Intranet-only app.** No CDN links, no external URLs.
- **`course_no` is the cross-revision course key** — group/merge courses by `course_no`, never by `courses.id`.
- **Name display:** staff → `display_name_th`; course columns → `course_no` linked to the course.
- **Task 5 is GATED:** do NOT start it until the human has explicitly confirmed tests should be written (project rule: ask before writing tests). Tasks 1–4 must not add or modify tests except where Task 3 says so (registry_test must be fixed there or the suite breaks).
- Verification smokes use the dev DB via `bin/rails runner` with an `ActionDispatch::Integration::Session` logged in as the seeded `root` user (`password123`). Dev DB has real schedule data (years up to 2569).

---

### Task 1: Teaching Matrix — route, controller action, view, schedules-index tile

**Files:**
- Modify: `config/routes.rb:40-41`
- Modify: `app/controllers/schedules_controller.rb` (insert action after `workload`, i.e. after line 154)
- Create: `app/views/schedules/teaching_matrix.html.haml`
- Modify: `app/views/schedules/index.html.haml` (new tile after the Staff Workload tile, line 41)

**Interfaces:**
- Consumes: `Teaching`, `Semester` (`SEMESTER_NUMBERS`, `SEMESTER_LABELS`, `display_name`), `Staff#display_name_th`, `Course#revision_year_be`, existing SCSS classes `.teaching-history-table` / `.th-rotated` (global in `application.scss`, no SCSS change needed).
- Produces: `GET /schedules/teaching_matrix` (helper `schedules_teaching_matrix_path`) accepting params `year` (B.E. integer), `semester_number` (1/2/3 or blank = whole year), `course_scope` (`"dept"` default | `"all"`). Task 4 links here; Task 5 tests it.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `controller :schedules do` block, between the workload and conflicts lines:

```ruby
    get "schedules/workload", action: :workload
    get "schedules/teaching_matrix", action: :teaching_matrix
    get "schedules/conflicts", action: :conflicts
```

- [ ] **Step 2: Add the controller action**

In `app/controllers/schedules_controller.rb`, insert between the end of `workload` (line 154) and `def conflicts`:

```ruby
  # Staff × course section-count matrix for one term or a whole academic year:
  # the department-wide "who taught what". A column slice is a course's
  # teachers (this absorbed the retired CourseTeachers report); a row slice is
  # one staff member's courses. Ranking and sorting stay workload's job, so
  # this renders as a plain table.
  def teaching_matrix
    default_year = Semester.joins(course_offerings: { sections: :teachings }).maximum(:year_be)
    @year = (params[:year].presence || default_year).to_i
    @semester_number = params[:semester_number].presence&.to_i
    @semester_number = nil unless Semester::SEMESTER_NUMBERS.include?(@semester_number)
    @course_scope = params[:course_scope] == "all" ? "all" : "dept"

    scope = Teaching.joins(section: { course_offering: [:course, :semester] })
                    .where(semesters: { year_be: @year })
    scope = scope.where(semesters: { semester_number: @semester_number }) if @semester_number
    scope = scope.where("courses.course_no LIKE ?", "2110%") if @course_scope == "dept"
    teachings = scope.includes(:staff, section: { course_offering: [:course, :semester] }).to_a

    # Columns: one per course_no (cross-revision key), labeled by the latest
    # revision — same merge rule as Staff#teaching_history.
    @columns = teachings.group_by { |t| t.section.course_offering.course.course_no }
                        .map do |course_no, ts|
                          latest = ts.map { |t| t.section.course_offering.course }.max_by(&:revision_year_be)
                          { course_no: course_no, name: latest.name, course: latest }
                        end
                        .sort_by { |c| c[:course_no] }

    # Cells: distinct sections per (staff, course_no). Tooltip lists section
    # numbers, term-qualified when the scope is a whole year.
    @cells = {}
    @totals = Hash.new(0)
    teachings.group_by { |t| [t.staff_id, t.section.course_offering.course.course_no] }
             .each do |(staff_id, course_no), ts|
      sections = ts.map(&:section).uniq
      @totals[staff_id] += sections.size
      tooltip = sections.group_by { |s| s.course_offering.semester }
                        .sort_by { |sem, _| sem.semester_number }
                        .map do |sem, secs|
                          nums = secs.map(&:section_number).sort.join(", ")
                          @semester_number ? "Section#{"s" if secs.size > 1} #{nums}" : "#{sem.display_name}: sec #{nums}"
                        end.join(" · ")
      @cells[[staff_id, course_no]] = { count: sections.size, tooltip: tooltip }
    end

    @staffs = Staff.where(id: teachings.map(&:staff_id).uniq).sort_by(&:display_name_th)
  end
```

- [ ] **Step 3: Create the view**

Create `app/views/schedules/teaching_matrix.html.haml`:

```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1.d-flex.align-items-center
    %span.material-symbols.resource-icon.me-2 grid_on
    Teaching Matrix
  = link_to "Back", schedules_path, class: "btn btn-outline-primary"

.card.mb-3
  .card-body.p-3
    = form_with(url: schedules_teaching_matrix_path, method: :get, class: "row g-2 align-items-end") do |f|
      .col-auto
        %label.form-label.mb-0 Year (B.E.)
        = number_field_tag :year, @year, class: "form-control form-control-sm", style: "width: 100px"
      .col-auto
        %label.form-label.mb-0 Semester
        = select_tag :semester_number, options_for_select(Semester::SEMESTER_NUMBERS.map { |n| [Semester::SEMESTER_LABELS[n], n] }, @semester_number), include_blank: "All", class: "form-select form-select-sm", style: "width: 120px"
      .col-auto
        %label.form-label.mb-0 Courses
        = select_tag :course_scope, options_for_select([["Department (2110xxx)", "dept"], ["All courses", "all"]], @course_scope), class: "form-select form-select-sm", style: "width: 180px"
      .col-auto
        %button.btn.btn-primary.btn-sm{type: "submit"}
          %span.material-symbols{style: "font-size: 16px; vertical-align: middle"} filter_list
          View

- if @columns.any?
  .card
    .card-body.p-3
      %h5.card-title= "Sections taught per lecturer — #{@semester_number ? "#{@year}/#{@semester_number}" : "#{@year} (all semesters)"}"
      .table-responsive
        %table.table.table-hover.mb-0.teaching-history-table
          %thead
            %tr
              %th Staff
              - @columns.each do |c|
                %th.th-rotated
                  = link_to c[:course_no], c[:course], title: c[:name]
              %th.text-center Σ
          %tbody
            - @staffs.each do |staff|
              %tr
                %td= link_to staff.display_name_th, staff_path(staff)
                - @columns.each do |c|
                  - cell = @cells[[staff.id, c[:course_no]]]
                  %td.text-center{title: cell && cell[:tooltip]}= cell && cell[:count]
                %td.text-center
                  %strong= @totals[staff.id]
- else
  .card
    .card-body.p-3
      %p.text-muted.mb-0 No teaching data found for this scope.
```

- [ ] **Step 4: Add the schedules-index tile**

In `app/views/schedules/index.html.haml`, insert between the Staff Workload tile (ends line 41) and the Conflict Detection tile:

```haml
  .col-md-4
    = link_to schedules_teaching_matrix_path, class: "text-decoration-none" do
      .card.schedule-report-card
        .card-body
          %span.material-symbols.schedule-report-icon grid_on
          %h6 Teaching Matrix
          %p Sections taught per lecturer per course
```

- [ ] **Step 5: Smoke-test against the dev DB**

Run:

```bash
bin/rails runner '
app = ActionDispatch::Integration::Session.new(Rails.application)
app.post "/login", params: { username: "root", password: "password123" }
app.get "/schedules/teaching_matrix"
raise "status #{app.response.status}" unless app.response.status == 200
body = app.response.body
raise "no matrix rendered" unless body.include?("teaching-history-table")
raise "no rotated headers" unless body.include?("th-rotated")
app.get "/schedules/teaching_matrix", params: { year: 2569, semester_number: 1, course_scope: "all" }
raise "filtered status #{app.response.status}" unless app.response.status == 200
app.get "/schedules/teaching_matrix", params: { year: 2500 }
raise "empty state missing" unless app.response.body.include?("No teaching data")
app.get "/schedules"
raise "tile missing" unless app.response.body.include?("Teaching Matrix")
puts "OK"'
```

Expected output: `OK`

- [ ] **Step 6: Run the existing schedules tests (regression only — add no tests)**

Run: `bin/rails test test/controllers/schedules_controller_test.rb test/controllers/schedules_workload_and_conflicts_test.rb`
Expected: all pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
hg commit -m "Add teaching matrix schedules report (staff × course section counts)

There was no department-wide \"who taught what\" view: staffs/show slices by
one staff, the CourseTeachers report by one course, and workload shows how
much but not which courses. This matrix shows all lecturers × all courses for
a term or academic year, with section counts in the cells.

- GET /schedules/teaching_matrix: year (B.E.) / semester (blank = whole year)
  / course scope (2110xxx default, all) filters
- plain table reusing the staffs/show teaching-history matrix styling;
  ranking stays workload's job
- 7th tile on the schedules index" config/routes.rb app/controllers/schedules_controller.rb app/views/schedules/teaching_matrix.html.haml app/views/schedules/index.html.haml
```

---

### Task 2: Teachers column on courses/show Offerings table

**Files:**
- Modify: `app/controllers/courses_controller.rb` (last line of `show`, the `@offerings` assignment)
- Modify: `app/views/courses/show.html.haml:86-103` (Offerings table)

**Interfaces:**
- Consumes: `CourseOffering#sections` → `Section#teachings` → `Teaching#staff`, `Staff#initials` / `#display_name_th`.
- Produces: the Offerings table gains a "Teachers" column between Sections and Status. This closes the retirement blocker for Task 3 (backlog item 2: "section counts but not teachers").

- [ ] **Step 1: Eager-load teachings in the controller**

In `app/controllers/courses_controller.rb`, `show` action, replace:

```ruby
    @offerings = @course.course_offerings.includes(:semester, :sections).order("semesters.year_be DESC, semesters.semester_number DESC").references(:semesters)
```

with:

```ruby
    @offerings = @course.course_offerings.includes(:semester, sections: { teachings: :staff }).order("semesters.year_be DESC, semesters.semester_number DESC").references(:semesters)
```

- [ ] **Step 2: Add the column to the view**

In `app/views/courses/show.html.haml`, in the Offerings table, replace:

```haml
            %tr
              %th Semester
              %th Sections
              %th Status
              %th Actions
```

with:

```haml
            %tr
              %th Semester
              %th Sections
              %th Teachers
              %th Status
              %th Actions
```

and replace the row body:

```haml
              %tr
                %td= "#{offering.semester.display_name} — #{Semester::SEMESTER_LABELS[offering.semester.semester_number]}"
                %td= offering.sections.size
                %td
                  %span.badge{class: "badge-#{offering.status.dasherize}"}= offering.status.titleize
```

with:

```haml
              %tr
                %td= "#{offering.semester.display_name} — #{Semester::SEMESTER_LABELS[offering.semester.semester_number]}"
                %td= offering.sections.size
                %td= safe_join(offering.sections.flat_map { |s| s.teachings.map(&:staff) }.uniq.map { |st| link_to(st.initials.presence || st.display_name_th, staff_path(st)) }, ", ")
                %td
                  %span.badge{class: "badge-#{offering.status.dasherize}"}= offering.status.titleize
```

- [ ] **Step 3: Smoke-test against the dev DB**

Run:

```bash
bin/rails runner '
app = ActionDispatch::Integration::Session.new(Rails.application)
app.post "/login", params: { username: "root", password: "password123" }
course = Course.joins(course_offerings: { sections: :teachings }).first!
app.get "/courses/#{course.id}"
raise "status #{app.response.status}" unless app.response.status == 200
raise "Teachers column missing" unless app.response.body.include?("<th>Teachers</th>")
puts "OK"'
```

Expected output: `OK`

- [ ] **Step 4: Run existing course tests (regression only — add no tests)**

Run: `bin/rails test test/controllers/courses_controller_test.rb test/controllers/course_offerings_controller_test.rb`
Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
hg commit -m "Show section teachers on the course page's Offerings table

Backlog item 2 blocked retiring the CourseTeachers report on exactly this
gap: courses/show listed section counts but not who teaches them (one click
away per offering). With teachers visible inline, the per-course view is
fully absorbed and the report can go (next commit).

Initials link to the staff page; falls back to the Thai display name for
staff without initials." app/controllers/courses_controller.rb app/views/courses/show.html.haml
```

---

### Task 3: Retire Reports::CourseTeachers

**Files:**
- Delete: `app/services/reports/course_teachers.rb` (via `hg rm`)
- Modify: `app/services/reports/registry.rb:15`
- Modify: `test/services/reports/registry_test.rb:24` (must be fixed in THIS task or the suite breaks — this is the one allowed test edit before Task 5)

**Interfaces:**
- Consumes: Tasks 1–2 must already be committed (they are the absorption that justifies deletion).
- Produces: `Reports::Registry.all` no longer contains `Reports::CourseTeachers`; the reports index page (registry-driven) stops listing "Who teaches this subject". The LINE bot is unaffected — it uses `GradeStats::` services, not `Reports::`.

- [ ] **Step 1: Remove the class file and registry entry**

```bash
hg rm app/services/reports/course_teachers.rb
```

In `app/services/reports/registry.rb`, remove the line:

```ruby
      Reports::CourseTeachers,
```

(the `REPORTS` array then starts with `Reports::FailingStudents`).

- [ ] **Step 2: Fix the registry test**

In `test/services/reports/registry_test.rb`, replace:

```ruby
    assert_includes Reports::Registry.grouped[:courses].map(&:key), "course_teachers"
```

with:

```ruby
    assert_includes Reports::Registry.grouped[:courses].map(&:key), "failing_students"
```

- [ ] **Step 3: Verify nothing else references the class**

Run: `grep -rn "CourseTeachers\|course_teachers" app/ test/ config/ lib/ 2>/dev/null`
Expected: no output (docs/ mentions are handled in Task 4; `docs/superpowers/` history stays as-is).

- [ ] **Step 4: Run the reports test suite**

Run: `bin/rails test test/services/reports/`
Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
hg commit -m "Retire the CourseTeachers web report

Both of its uses are now absorbed: courses/show lists each offering's
teachers inline (previous commit), and the new teaching-matrix schedules
report answers the cross-course \"who teaches what\" question — one matrix
column is this entire report for a term. Backlog item 2 planned exactly this
retirement once the absorption gap closed.

The LINE bot is unaffected: it uses GradeStats:: services, not Reports::." app/services/reports/course_teachers.rb app/services/reports/registry.rb test/services/reports/registry_test.rb
```

---

### Task 4: Cross-link from staffs/show + docs + backlog updates

**Files:**
- Modify: `app/views/staffs/show.html.haml` (per-semester Teaching card, after the `- if @teachings.any?` / `- else` block that ends line 122)
- Modify: `CLAUDE.md:143`
- Modify: `docs/schedule-reports.md` (Reports Overview table line ~21, new Report 7 section before `## Routes` line ~283, Routes listing)
- Modify: `docs/backlog.md` (items 1 and 2)

**Interfaces:**
- Consumes: `schedules_teaching_matrix_path` (Task 1), `@selected_semester` (already set by `StaffsController#show` whenever the Teaching card renders).
- Produces: documentation only; no code contracts.

- [ ] **Step 1: Add the cross-link on staffs/show**

In `app/views/staffs/show.html.haml`, the Teaching card currently ends:

```haml
      - if @teachings.any?
        .table-responsive
          %table.table.table-hover.mb-0
            ...
      - else
        %p.text-muted.mb-0 No teaching assignments for this semester.
```

Append directly after the `- else` branch's line, at the same indentation as `- if @teachings.any?` (6 spaces):

```haml
      %p.text-muted.small.mt-2.mb-0
        = link_to "Department-wide teaching matrix for #{@selected_semester.display_name} →", schedules_teaching_matrix_path(year: @selected_semester.year_be, semester_number: @selected_semester.semester_number)
```

- [ ] **Step 2: Update CLAUDE.md**

In `CLAUDE.md` line 143, replace:

```markdown
- **Schedule reports**: `SchedulesController` with 6 read-only reports (room, staff, workload, curriculum, student, conflicts). Shared `_week_calendar.html.haml` partial accepts `entries` array of hashes. See `docs/schedule-reports.md`.
```

with:

```markdown
- **Schedule reports**: `SchedulesController` with 7 read-only reports (room, staff, workload, curriculum, student, conflicts, teaching matrix). Shared `_week_calendar.html.haml` partial accepts `entries` array of hashes. See `docs/schedule-reports.md`.
```

- [ ] **Step 3: Update docs/schedule-reports.md**

3a. In the Reports Overview table, add after the row for report 6:

```markdown
| 7 | **Teaching Matrix** | year, semester (optional), course scope | staff × course matrix | admin |
```

3b. Insert a new section immediately before `## Routes`:

```markdown
## Report 7: Teaching Matrix

**Question:** "Who taught what across the department in a term or year?"

Added 2026-07-16 (spec:
`docs/superpowers/specs/2026-07-16-teaching-matrix-report-design.md`). Absorbed
the retired `Reports::CourseTeachers` web report — one matrix column is that
entire report for a term.

- **Filters**: `year` (B.E., defaults to the latest year with teachings),
  `semester_number` (blank = whole academic year), `course_scope`
  (`dept` = `course_no LIKE '2110%'`, default; `all`)
- **Display**: staff rows × `course_no` columns (rotated headers, reusing the
  staffs/show `.teaching-history-table` styling), cells = distinct section
  count with section numbers in the tooltip (term-qualified for whole-year
  scope), Σ total column. Plain table — no DataTables; ranking/sorting is the
  Staff Workload report's job.
- **Query**: one `Teaching` join through section → course_offering →
  course/semester, pivoted in Ruby; columns keyed by cross-revision
  `course_no`.
```

3c. In the `## Routes` section's code block, add alongside the other schedules routes:

```ruby
get "schedules/teaching_matrix", action: :teaching_matrix
```

- [ ] **Step 4: Update docs/backlog.md**

4a. Item 1 seed list — replace the courses/show bullet:

```markdown
- **courses/show** → `failing_students` (course_no pre-filled) and
  `course_teachers` (course_no + semester) — see also item 2 before adding
  the latter.
```

with:

```markdown
- **courses/show** → `failing_students` (course_no pre-filled).
```

and add a new bullet at the end of the seed list:

```markdown
- **staffs/show** (per-semester Teaching card) → `/schedules/teaching_matrix`
  pre-filled with the selected semester: the department-wide view of the same
  term. Link added 2026-07-16.
```

4b. Item 2 — replace the `course_teachers` bullet:

```markdown
- `course_teachers` — mostly absorbed by courses/show; the gap is that the
  Offerings table shows section counts but not teachers (they're one click away
  on the offering page). Adding a Teachers column there would fully absorb it →
  then retire.
```

with:

```markdown
- `course_teachers` — **retired 2026-07-16**: courses/show Offerings gained a
  Teachers column and the teaching-matrix schedules report covers the
  cross-course view.
```

and add a new bullet at the end of the item 2 list:

```markdown
- `teaching_matrix` (at `/schedules`, not the registry) — set/aggregate report
  (staff × course per term/year), no single-entity anchor. Keep regardless.
```

- [ ] **Step 5: Smoke-test the cross-link**

Run:

```bash
bin/rails runner '
app = ActionDispatch::Integration::Session.new(Rails.application)
app.post "/login", params: { username: "root", password: "password123" }
staff = Staff.joins(:teachings).first!
app.get "/staffs/#{staff.id}"
raise "status #{app.response.status}" unless app.response.status == 200
raise "matrix link missing" unless app.response.body.include?("schedules/teaching_matrix?")
puts "OK"'
```

Expected output: `OK`

- [ ] **Step 6: Commit**

```bash
hg commit -m "Cross-link staffs/show to the teaching matrix; record it in docs + backlog

Backlog item 1 requires every report adjacent to an entity page to be linked
from that page with params pre-filled: the staff Teaching card shows one
lecturer's term, the matrix shows everyone's, so the card now links to the
matrix for the selected semester. Backlog item 2 records the CourseTeachers
retirement and classifies teaching_matrix as a set-level report (keep
regardless); schedule-reports.md and CLAUDE.md now count 7 reports." app/views/staffs/show.html.haml CLAUDE.md docs/schedule-reports.md docs/backlog.md
```

---

### Task 5: Tests (GATED — requires explicit human go-ahead first)

**Do not start this task until the human has confirmed tests should be written.**

**Files:**
- Modify: `test/fixtures/semesters.yml`, `test/fixtures/course_offerings.yml`, `test/fixtures/sections.yml`, `test/fixtures/teachings.yml`
- Modify: `test/controllers/schedules_controller_test.rb`
- Modify: `test/controllers/courses_controller_test.rb`
- Modify: `test/system/schedules_test.rb` (one `assert_text` in the landing-page test)

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces: fixture keys `sem_2567_1`, `sem_2567_2`, `intro_computing_2567_1`, `gened_2567_1`, `intro_computing_2567_2`, `intro_2567_sec1`, `intro_2567_sec33`, `gened_2567_sec1`, `intro_2567_2_sec2`, `smith_2567_intro1`, `smith_2567_intro33`, `smith_2567_2_intro2`, `jones_2567_gened`.

**Coverage note:** the spec's "system test happy path" (a staff row showing the right count in the right column) is deliberately covered by the Nokogiri-based controller tests below instead of a Capybara test — same assertions, no headless-Firefox cost. The system suite only gains a landing-tile assertion.

**Fixture strategy (why year 2567):** the existing workload tests assert exact cell values, totals, and row order for an explicit 2568–2568 range, and the exporter test counts rows in `sem_2568_1` — new teachings in 2568 would break them. Year 2567 is excluded by every explicit-range assertion, doesn't change the workload default end-year (`Semester.maximum(:year_be)` stays 2568), doesn't collide with the semesters system test (which creates 2567/**3**; fixtures add only 2567/1 and 2567/2), and gives the matrix tests a fully controlled sandbox year.

- [ ] **Step 1: Add fixtures**

Append to `test/fixtures/semesters.yml`:

```yaml
sem_2567_1:
  year_be: 2567
  semester_number: 1

sem_2567_2:
  year_be: 2567
  semester_number: 2
```

Append to `test/fixtures/course_offerings.yml`:

```yaml
intro_computing_2567_1:
  course: intro_computing
  semester: sem_2567_1
  status: confirmed

gened_2567_1:
  course: gened_course
  semester: sem_2567_1
  status: confirmed

intro_computing_2567_2:
  course: intro_computing
  semester: sem_2567_2
  status: confirmed
```

Append to `test/fixtures/sections.yml`:

```yaml
intro_2567_sec1:
  course_offering: intro_computing_2567_1
  section_number: 1

intro_2567_sec33:
  course_offering: intro_computing_2567_1
  section_number: 33

gened_2567_sec1:
  course_offering: gened_2567_1
  section_number: 1

intro_2567_2_sec2:
  course_offering: intro_computing_2567_2
  section_number: 2
```

Append to `test/fixtures/teachings.yml`:

```yaml
smith_2567_intro1:
  section: intro_2567_sec1
  staff: lecturer_smith
  load_ratio: 1.0

smith_2567_intro33:
  section: intro_2567_sec33
  staff: lecturer_smith
  load_ratio: 1.0

smith_2567_2_intro2:
  section: intro_2567_2_sec2
  staff: lecturer_smith
  load_ratio: 1.0

jones_2567_gened:
  section: gened_2567_sec1
  staff: lecturer_jones
  load_ratio: 1.0
```

- [ ] **Step 2: Run the FULL suite to prove the fixtures are inert**

Run: `bin/rails test`
Expected: all pass, 0 failures. If a count/order-sensitive test fails, the fixture sandboxing assumption broke — STOP and report; do not paper over by editing unrelated assertions.

- [ ] **Step 3: Add matrix controller tests**

Append inside the class in `test/controllers/schedules_controller_test.rb`:

```ruby
  test "teaching matrix defaults to the latest year with teachings" do
    get schedules_teaching_matrix_path
    assert_response :success
    assert_select "input#year[value=?]", "2568"
  end

  test "teaching matrix counts distinct sections per staff per course" do
    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1 }
    assert_response :success
    doc = Nokogiri::HTML(response.body)
    smith_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_smith).display_name_th) }
    assert smith_row, "smith row missing"
    # Dept scope (default): only 2110101 (sections 1 + 33) counts; column cell 2, total 2.
    assert_equal ["2", "2"], smith_row.css("td")[1..].map { |td| td.text.strip }
    # Jones only teaches the non-department gened course in 2567 → no row at all.
    assert_nil doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_jones).display_name_th) }
  end

  test "teaching matrix course scope toggles non-department columns" do
    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1 }
    assert_select "thead th a", text: "2103106", count: 0

    get schedules_teaching_matrix_path, params: { year: 2567, semester_number: 1, course_scope: "all" }
    assert_select "thead th a", text: "2103106"
    doc = Nokogiri::HTML(response.body)
    jones_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_jones).display_name_th) }
    assert jones_row, "jones row missing in all-courses scope"
  end

  test "teaching matrix whole-year scope sums semesters and qualifies tooltips" do
    get schedules_teaching_matrix_path, params: { year: 2567 }
    assert_response :success
    doc = Nokogiri::HTML(response.body)
    smith_row = doc.css("tbody tr").find { |tr| tr.text.include?(staffs(:lecturer_smith).display_name_th) }
    assert smith_row, "smith row missing"
    # 2 sections in 2567/1 + 1 in 2567/2 = 3, and 3 total.
    assert_equal ["3", "3"], smith_row.css("td")[1..].map { |td| td.text.strip }
    tooltip = smith_row.css("td[title]").first["title"]
    assert_includes tooltip, "2567/1: sec 1, 33"
    assert_includes tooltip, "2567/2: sec 2"
  end

  test "teaching matrix with no data shows the empty state" do
    get schedules_teaching_matrix_path, params: { year: 2500 }
    assert_response :success
    assert_match(/No teaching data/, response.body)
  end
```

- [ ] **Step 4: Run the matrix tests**

Run: `bin/rails test test/controllers/schedules_controller_test.rb`
Expected: all pass, 0 failures.

- [ ] **Step 5: Add the Teachers-column test**

Append inside the class in `test/controllers/courses_controller_test.rb`:

```ruby
  test "show lists each offering's teachers as staff links" do
    get course_path(courses(:intro_computing))
    assert_response :success
    assert_select "th", text: "Teachers"
    # intro_computing 2568/1: smith (JS) teaches sec 1+2, jones (JJ) co-teaches sec 2.
    assert_select "td a", text: "JS"
    assert_select "td a", text: "JJ"
  end
```

- [ ] **Step 6: Extend the schedules landing-page system test**

In `test/system/schedules_test.rb`, in the `"landing page shows report cards"` test, add after `assert_text "Staff Workload"`:

```ruby
    assert_text "Teaching Matrix"
```

- [ ] **Step 7: Run the affected suites, then the full suite**

Run: `bin/rails test test/controllers/courses_controller_test.rb && bin/rails test`
Expected: all pass, 0 failures.
Then (needs headless Firefox): `bin/rails test:system`
Expected: all pass. If the system-test environment is unavailable, report that instead of skipping silently.

- [ ] **Step 8: Commit**

```bash
hg commit -m "Test the teaching matrix report and the offerings Teachers column

Fixtures live in a new sandbox year (2567) because the workload tests assert
exact cell values and row order for an explicit 2568 range and the exporter
test counts rows in sem_2568_1 — 2567 is invisible to all of them while
giving the matrix tests both a single-term and a whole-year scenario, plus a
non-department (2103106) course to prove the dept/all scope toggle." test/fixtures/semesters.yml test/fixtures/course_offerings.yml test/fixtures/sections.yml test/fixtures/teachings.yml test/controllers/schedules_controller_test.rb test/controllers/courses_controller_test.rb test/system/schedules_test.rb
```
