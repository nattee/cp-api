# Report Hub Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two disconnected report hubs (`/reports` admin-only, `/schedules` under Teaching) and the `/grades/distribution` orphan with a single lecturer-facing `/reports` hub, driven by one catalog, with per-report access gating.

**Architecture:** A new `Reports::Catalog` (presentation/navigation layer) lists every report — both the generic-framework "registry" reports (rendered by `ReportsController#show`) and the "external" reports that render in their own controllers (`schedules/*`, `grades/distribution`) — with each report's hub section, one-line description, access level, and route. The hub view and the sidebar render from this catalog. Report internals and entity show pages are untouched. `data_coverage` becomes a `:system` catalog entry (admin-only, not shown in the hub); it is already linked from the Data Sources page.

**Tech Stack:** Ruby 3.4 / Rails 8.1, HAML views, Minitest + fixtures (unit/integration), Capybara + Selenium headless Firefox (system), Mercurial (hg) for VCS.

## Global Constraints

- **VCS is Mercurial (hg), NOT git.** There is no `.git`. Every commit step uses `hg`. Name explicit files in every `hg commit` — the repo often has unrelated dirty changes; never commit with a bare `hg commit`.
- **Commit messages lead with WHY** (the problem/motivation) in the first paragraph, then a bullet list of what changed. End with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **All users are lecturers.** Every hub report is open to any logged-in user (`access: :all`). The **only** admin-gated report is `data_coverage` (`access: :admin`, `section: :system`).
- **Do not touch** entity show pages (students/programs/courses/staffs/semesters/course_offerings) or any report's internal query/presentation. This is a navigation/catalog change only.
- **Views are HAML.** Follow the index-page layout convention: title row inside `.card-body.p-3` with `.d-flex.justify-content-between.align-items-center.mb-3` and an `%h5.card-title`.
- **Run tests:** unit/integration `bin/rails test <path>`; system `bin/rails test:system <path>`. Login in integration tests: `post login_path, params: { username: users(:viewer).username, password: "password123" }`. Login in system tests: visit `login_path`, fill "Username"/"Password", click "Sign In". Non-admin fixture user: `users(:viewer)`; admin: `users(:admin)`.

---

## File Structure

**Create:**
- `app/services/reports/catalog_entry.rb` — value object for one navigable report.
- `app/services/reports/catalog.rb` — the single source of truth: sections, entries, lookup, grouping.
- `app/helpers/reports_helper.rb` — `catalog_report_path(entry)` resolves an entry to its URL.
- `test/services/reports/catalog_test.rb` — unit tests for the catalog.
- `test/controllers/reports_controller_test.rb` — per-report gating + hub index.
- `test/system/reports_hub_test.rb` — hub sections/cards/navigation + sidebar.

**Modify:**
- `app/controllers/reports_controller.rb` — drop blanket `require_admin`; catalog-driven index + per-report gate on show.
- `app/views/reports/index.html.haml` — render from `@entries_by_section` with new sections.
- `app/views/layouts/application.html.haml` — one top-level "Reports" nav item; remove Teaching "Schedules" item and admin "Reports" item.
- `app/controllers/schedules_controller.rb` — `index` redirects to the hub.
- `test/controllers/schedules_controller_test.rb` — index now redirects.
- `test/system/schedules_test.rb` — landing test becomes a redirect assertion.
- `docs/backlog.md`, `docs/schedule-reports.md` — reflect the one-hub consolidation.

**Delete:**
- `app/views/schedules/index.html.haml` — the old schedules landing page (now a redirect).

**Left intact (do NOT change):** `app/services/reports/registry.rb` and its `test/services/reports/registry_test.rb` (Registry stays the canonical list of framework report classes; Catalog is the presentation layer over all reports and is verified to cover Registry).

---

### Task 1: Report catalog (value object + catalog module)

**Files:**
- Create: `app/services/reports/catalog_entry.rb`
- Create: `app/services/reports/catalog.rb`
- Test: `test/services/reports/catalog_test.rb`

**Interfaces:**
- Consumes: existing report classes `Reports::FailingStudents`, `Reports::SemesterGradeDistribution`, `Reports::CohortGpa`, `Reports::GroupCreditShortfall`, `Reports::ThesisCredits`, `Reports::StaffCoursesByYear`, `Reports::DataCoverage` (each responds to `.key`, `.title`, `.applicable_to?(group)`); `Reports::Registry.all`.
- Produces:
  - `Reports::CatalogEntry` — `Struct` with members `key, title, description, section, access, path_helper, report_class`; instance methods `registry?`, `hub?`, `applicable_to?(group)`.
  - `Reports::Catalog` — module methods `SECTIONS` (Hash), `entries -> [CatalogEntry]`, `hub_entries -> [CatalogEntry]`, `find(key) -> CatalogEntry | nil`, `grouped(list = hub_entries) -> {section => [CatalogEntry]}`.

- [ ] **Step 1: Write the failing test**

Create `test/services/reports/catalog_test.rb`:

```ruby
require "test_helper"

class Reports::CatalogTest < ActiveSupport::TestCase
  test "report keys are unique" do
    keys = Reports::Catalog.entries.map(&:key)
    assert_equal keys.uniq, keys
  end

  test "every framework report is present in the catalog" do
    Reports::Registry.all.each do |klass|
      assert Reports::Catalog.find(klass.key), "#{klass.key} missing from catalog"
    end
  end

  test "hub entries exclude the system section and are all hub?" do
    assert Reports::Catalog.hub_entries.none? { |e| e.section == :system }
    assert Reports::Catalog.hub_entries.all?(&:hub?)
  end

  test "data coverage is an admin-gated system report, absent from the hub" do
    dc = Reports::Catalog.find("data_coverage")
    assert_equal :system, dc.section
    assert_equal :admin, dc.access
    assert_not dc.hub?
    assert Reports::Catalog.hub_entries.none? { |e| e.key == "data_coverage" }
  end

  test "all hub entries are open to any logged-in user" do
    assert Reports::Catalog.hub_entries.all? { |e| e.access == :all }
  end

  test "registry entries wrap a report class; external entries carry a path helper" do
    Reports::Catalog.entries.each do |e|
      if e.registry?
        assert e.report_class < Reports::Base, "#{e.key} should wrap a Reports::Base subclass"
        assert_nil e.path_helper
      else
        assert_not_nil e.path_helper, "#{e.key} needs a path helper"
        assert_nil e.report_class
      end
    end
  end

  test "schedules vs teaching split is as designed" do
    assert_equal :schedules, Reports::Catalog.find("schedules_room").section
    assert_equal :teaching, Reports::Catalog.find("schedules_workload").section
    assert_equal "Staff Workload", Reports::Catalog.find("schedules_workload").title
  end

  test "the two grade-distribution reports have distinct titles" do
    assert_equal "Grade distribution by course", Reports::Catalog.find("semester_grade_distribution").title
    assert_equal "Class Grade Distribution", Reports::Catalog.find("grades_distribution").title
  end

  test "grouped orders sections per SECTIONS and omits system" do
    order = Reports::Catalog.grouped.keys
    assert_equal order, order.sort_by { |s| Reports::Catalog::SECTIONS.keys.index(s) }
    assert_not_includes order, :system
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/reports/catalog_test.rb`
Expected: FAIL — `uninitialized constant Reports::Catalog`.

- [ ] **Step 3: Create the value object**

Create `app/services/reports/catalog_entry.rb`:

```ruby
module Reports
  # One navigable report in the hub / sidebar, whether it renders through the
  # generic ReportsController framework (a "registry" report, report_class set)
  # or in its own controller (an "external" report, path_helper set).
  CatalogEntry = Struct.new(
    :key, :title, :description, :section, :access, :path_helper, :report_class,
    keyword_init: true
  ) do
    def registry? = report_class.present?

    # System reports (e.g. Data Coverage) are admin operational checks, not
    # lecturer analytics — reachable by their route, never listed in the hub.
    def hub? = section != :system

    # External reports are program-agnostic; registry reports may be scoped
    # (e.g. Thesis Credits is master-only) via the report class.
    def applicable_to?(group) = registry? ? report_class.applicable_to?(group) : true
  end
end
```

- [ ] **Step 4: Create the catalog**

Create `app/services/reports/catalog.rb`:

```ruby
module Reports
  # Single source of truth for every report the app exposes and how the hub +
  # sidebar present them. Section assignment and card copy live HERE (the
  # presentation layer), not on the report classes — a report's analytical
  # identity is separate from which hub drawer it sits in, and external reports
  # have no report class to hold that metadata. Registry reports render through
  # ReportsController#show; external reports render in their own controllers and
  # are listed here only for navigation.
  module Catalog
    # Display order + labels. :system is never shown in the hub.
    SECTIONS = {
      schedules: "Schedules",
      teaching:  "Teaching",
      grades:    "Grades & Courses",
      students:  "Students & Cohorts",
      system:    "System"
    }.freeze

    module_function

    def entries
      [
        # --- Schedules (timetables + the "is my timetable broken?" check) ---
        external("schedules_room",            "Room Schedule",        "Room usage across the week for a semester",        :schedules, :schedules_room_path),
        external("schedules_staff",           "Staff Schedule",       "A lecturer's weekly timetable and load",           :schedules, :schedules_staff_path),
        external("schedules_student",         "Student Timetable",    "A student's weekly schedule with grades",          :schedules, :schedules_student_path),
        external("schedules_curriculum",      "Curriculum Calendar",  "Combined weekly calendar for a set of courses",    :schedules, :schedules_curriculum_path),
        external("schedules_conflicts",       "Conflict Detection",   "Room and staff double-bookings for a semester",    :schedules, :schedules_conflicts_path),
        # --- Teaching (teaching analytics: matrices + per-lecturer year) ---
        external("schedules_workload",        "Staff Workload",       "Teaching load per lecturer across semesters",      :teaching, :schedules_workload_path),
        external("schedules_teaching_matrix", "Teaching Matrix",      "Sections taught per lecturer per course",          :teaching, :schedules_teaching_matrix_path),
        registry(Reports::StaffCoursesByYear, "Courses and co-lecturers a lecturer taught in a year, with seats", :teaching),
        # --- Grades & Courses ---
        registry(Reports::SemesterGradeDistribution, "Per-course grade counts and GPA for a program and term", :grades),
        external("grades_distribution",       "Class Grade Distribution", "Grade spread and pass rate per subject across terms", :grades, :distribution_grades_path),
        registry(Reports::FailingStudents,    "Students who received F in a course and term", :grades),
        # --- Students & Cohorts ---
        registry(Reports::CohortGpa,          "Per-term GPA and GPAX for one admission cohort", :students),
        registry(Reports::GroupCreditShortfall, "Students below a credit threshold in a course group", :students),
        registry(Reports::ThesisCredits,      "Enrolled thesis credits per student (master programs)", :students),
        # --- System (admin operational check; not shown in the hub) ---
        registry(Reports::DataCoverage,       "Per-term data-coverage matrix with gaps flagged", :system, access: :admin)
      ]
    end

    def hub_entries
      entries.select(&:hub?)
    end

    def find(key)
      entries.find { |e| e.key == key }
    end

    # Groups by section in SECTIONS order; only sections present appear.
    def grouped(list = hub_entries)
      list.group_by(&:section)
          .sort_by { |section, _| SECTIONS.keys.index(section) }
          .to_h
    end

    def external(key, title, description, section, path_helper)
      CatalogEntry.new(key: key, title: title, description: description,
                       section: section, access: :all, path_helper: path_helper,
                       report_class: nil)
    end

    def registry(klass, description, section, access: :all)
      CatalogEntry.new(key: klass.key, title: klass.title, description: description,
                       section: section, access: access, path_helper: nil,
                       report_class: klass)
    end
  end
end
```

Note: `entries` is rebuilt on each call (no memoization) so it re-resolves report-class constants — safe under Zeitwerk reloading in development. It is ~15 tiny objects; cost is negligible.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/services/reports/catalog_test.rb`
Expected: PASS (all assertions).

- [ ] **Step 6: Commit**

```bash
hg add app/services/reports/catalog_entry.rb app/services/reports/catalog.rb test/services/reports/catalog_test.rb
hg commit app/services/reports/catalog_entry.rb app/services/reports/catalog.rb test/services/reports/catalog_test.rb -m "Reports live in two hubs split by controller, not by user question

Introduce a single report catalog so the hub and sidebar can be driven from one
source of truth. It lists every report — framework 'registry' reports and
'external' reports that render in their own controllers (schedules/*,
grades/distribution) — with each report's hub section, description, access
level, and route. Data Coverage is marked :system/:admin so it stays out of the
lecturer hub. This is the data layer only; controller and views follow.

- Add Reports::CatalogEntry value object (registry? / hub? / applicable_to?)
- Add Reports::Catalog (SECTIONS, entries, hub_entries, find, grouped)
- Unit tests: uniqueness, Registry coverage, gating, section split, titles

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Per-report gating + catalog-driven hub index (controller)

**Files:**
- Modify: `app/controllers/reports_controller.rb`
- Test: `test/controllers/reports_controller_test.rb`

**Interfaces:**
- Consumes: `Reports::Catalog.hub_entries`, `Reports::Catalog.find(key)`, `Reports::Catalog.grouped(list)`; `CatalogEntry#applicable_to?`, `#registry?`, `#access`, `#report_class`.
- Produces: `@entries_by_section` (`{section => [CatalogEntry]}`) for the index view; `@report` (a `Reports::Base` subclass) for the show view, unchanged downstream.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/reports_controller_test.rb`:

```ruby
require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { username: user.username, password: "password123" }
  end

  test "a non-admin lecturer can open the reports hub" do
    login users(:viewer)
    get reports_path
    assert_response :success
  end

  test "a non-admin lecturer can open a registry hub report" do
    login users(:viewer)
    get report_path("failing_students")
    assert_response :success
  end

  test "a non-admin cannot open the admin-only data coverage report" do
    login users(:viewer)
    get report_path("data_coverage")
    assert_redirected_to root_path
  end

  test "an admin can open the data coverage report" do
    login users(:admin)
    get report_path("data_coverage")
    assert_response :success
  end

  test "an unknown report key redirects back to the hub" do
    login users(:viewer)
    get report_path("no_such_report")
    assert_redirected_to reports_path
  end

  test "the program filter narrows the hub to applicable reports" do
    login users(:viewer)
    get reports_path, params: { program_group: "CP" }
    assert_response :success
    # Thesis Credits is master-only; CP is a bachelor group, so its card is hidden.
    assert_select "a.card .card-title", text: "Thesis credits per student", count: 0
    # A program-agnostic schedules card is still present.
    assert_select "a.card .card-title", text: "Room Schedule"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/reports_controller_test.rb`
Expected: FAIL — the viewer is redirected by the current blanket `require_admin` (so "can open the reports hub" fails), and `@entries_by_section` does not exist yet.

- [ ] **Step 3: Rewrite the controller**

Replace the entire contents of `app/controllers/reports_controller.rb` with:

```ruby
class ReportsController < ApplicationController
  # Access is per-report (see Reports::Catalog), not a blanket controller gate:
  # every hub report is open to any logged-in lecturer; only :admin reports
  # (Data Coverage) are restricted.

  # Hub: lecturer-facing reports grouped by section, optional program filter.
  def index
    @program_groups = ProgramGroup.order(:code)
    @selected_group = @program_groups.find_by(code: params[:program_group]) if params[:program_group].present?
    entries = Reports::Catalog.hub_entries
    entries = entries.select { |e| e.applicable_to?(@selected_group) } if @selected_group
    @entries_by_section = Reports::Catalog.grouped(entries)
  end

  # One framework report: render its param form, and (when run) its result / CSV.
  def show
    entry = Reports::Catalog.find(params[:id])
    return redirect_to(reports_path, alert: "Unknown report.") unless entry&.registry?
    if entry.access == :admin && !current_user.admin?
      return redirect_to(root_path, alert: "Only admins can view that report.")
    end
    @report = entry.report_class

    if params[:run].present?
      missing = @report.params_spec.select { |p| p[:required] && params[p[:name]].blank? }
      if missing.any?
        flash.now[:alert] = "Please fill in: #{missing.map { |p| p[:name].to_s.humanize }.join(', ')}"
      else
        @result = @report.new(report_params).run
      end
    end

    respond_to do |format|
      format.html
      format.csv do
        @result ||= @report.new(report_params).run
        exporter = Exporters::ReportExporter.new(@result, filename: @report.key)
        send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
      end
    end
  end

  private

  # Whitelist: only the report's declared params, by name.
  def report_params
    @report.params_spec.each_with_object({}) { |p, h| h[p[:name].to_s] = params[p[:name]] }
  end
end
```

Key changes from the old version: removed `before_action :require_admin` and the private `require_admin` method; `index` now builds `@entries_by_section` from the catalog; `show` looks up a `CatalogEntry`, redirects unknown/non-registry keys, and enforces the per-report `:admin` gate before rendering.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/controllers/reports_controller_test.rb`
Expected: FAIL on the `assert_select` cases — the index **view** still references the old `@reports_by_section`. That is Task 3. The non-view tests (hub success, registry report success, data_coverage gating, unknown key) should PASS now.

To confirm just the non-view behavior at this step:
Run: `bin/rails test test/controllers/reports_controller_test.rb -n "/can open|cannot open|unknown report/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg add test/controllers/reports_controller_test.rb
hg commit app/controllers/reports_controller.rb test/controllers/reports_controller_test.rb -m "Six lecturer reports were locked behind an admin gate meant for one

ReportsController applied a blanket require_admin because a single report in it
(Data Coverage) is admin-only. That gate hid failing-students, grade
distribution, cohort GPA and the rest from the lecturers who need them. Move
gating to per-report: read each report's access from the catalog, so only Data
Coverage stays admin-only and every other report opens to any logged-in
lecturer. The hub index now renders from the catalog.

- Drop before_action :require_admin; gate show on the catalog entry's :access
- index builds @entries_by_section from Reports::Catalog.grouped
- Integration tests for the new gating and program filter (view assertions
  land green after the hub view task)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Hub view + path helper

**Files:**
- Create: `app/helpers/reports_helper.rb`
- Modify: `app/views/reports/index.html.haml`
- Test: `test/system/reports_hub_test.rb`

**Interfaces:**
- Consumes: `@entries_by_section` (from Task 2), `@program_groups`; `CatalogEntry#title`, `#description`, `#key`, `#path_helper`; `Reports::Catalog::SECTIONS`.
- Produces: `catalog_report_path(entry)` helper returning the URL string for an entry.

- [ ] **Step 1: Write the failing test**

Create `test/system/reports_hub_test.rb`:

```ruby
require "application_system_test_case"

class ReportsHubTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "hub shows the four lecturer sections with cards" do
    sign_in users(:viewer)
    visit reports_path

    assert_text "Schedules"
    assert_text "Teaching"
    assert_text "Grades & Courses"
    assert_text "Students & Cohorts"

    assert_link "Room Schedule"
    assert_link "Staff Workload"
    assert_link "Class Grade Distribution"
    assert_link "Cohort GPA by semester"
  end

  test "data coverage does not appear on the hub" do
    sign_in users(:admin)
    visit reports_path
    assert_no_text "Which terms are missing data"
  end

  test "a schedules card navigates to its report" do
    sign_in users(:viewer)
    visit reports_path
    click_on "Room Schedule"
    assert_current_path schedules_room_path
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test:system test/system/reports_hub_test.rb`
Expected: FAIL — the current view raises on the missing `@reports_by_section`, so `reports_path` errors.

- [ ] **Step 3: Add the path helper**

Create `app/helpers/reports_helper.rb`:

```ruby
module ReportsHelper
  # Resolves a catalog entry to its URL. Registry reports go through the generic
  # ReportsController#show (report_path/:id); external reports use their own
  # route helper (e.g. schedules_room_path, distribution_grades_path).
  def catalog_report_path(entry)
    entry.path_helper ? public_send(entry.path_helper) : report_path(entry.key)
  end
end
```

- [ ] **Step 4: Rewrite the hub view**

Replace the entire contents of `app/views/reports/index.html.haml` with:

```haml
-# app/views/reports/index.html.haml
.card
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon("reports")
        Reports
      = form_with url: reports_path, method: :get, class: "d-flex align-items-end gap-2" do
        .d-flex.flex-column
          = label_tag :program_group, "Program", class: "form-label small text-muted mb-1"
          = select_tag :program_group,
              options_for_select([["All programs", ""]] + @program_groups.map { |g| [g.code, g.code] }, params[:program_group]),
              class: "form-select form-select-sm"
        = submit_tag "Apply", class: "btn btn-outline-secondary btn-sm"

    - if @entries_by_section.empty?
      %p.text-body-secondary.mb-0 No reports for this program.
    - @entries_by_section.each do |section_key, entries|
      .mb-4
        %h6.text-uppercase.text-body-secondary.small.fw-semibold.mb-2= Reports::Catalog::SECTIONS[section_key]
        .row.g-3
          - entries.each do |entry|
            .col-md-4
              = link_to catalog_report_path(entry), class: "card h-100 text-decoration-none" do
                .card-body
                  %h6.card-title.mb-1= entry.title
                  %p.small.text-body-secondary.mb-0= entry.description
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test:system test/system/reports_hub_test.rb`
Expected: PASS.

Run: `bin/rails test test/controllers/reports_controller_test.rb`
Expected: PASS (the `assert_select` view assertions from Task 2 are now satisfied).

- [ ] **Step 6: Commit**

```bash
hg add app/helpers/reports_helper.rb test/system/reports_hub_test.rb
hg commit app/helpers/reports_helper.rb app/views/reports/index.html.haml test/system/reports_hub_test.rb -m "The reports hub listed only 7 of ~15 reports and hid the rest

Render the hub from the catalog so every lecturer-facing report — schedule
timetables, teaching analytics, grade and cohort reports — appears under one
honest door, grouped into the four sections a lecturer thinks in. Cards link
through a single helper that resolves both framework and external reports. Data
Coverage, being :system, is absent from the hub (it stays linked from Data
Sources).

- Add catalog_report_path helper (registry via report_path, external via own route)
- Rewrite reports/index to iterate @entries_by_section with entry titles/descriptions
- System tests: four sections, key cards, card navigation, Data Coverage absent

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Sidebar — one "Reports" door

**Files:**
- Modify: `app/views/layouts/application.html.haml`
- Test: `test/system/reports_hub_test.rb` (add one test)

**Interfaces:**
- Consumes: `reports_path`, `resource_icon("reports")`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Append this test to `test/system/reports_hub_test.rb` (inside the class):

```ruby
  test "sidebar shows one Reports item and no separate Schedules item for a lecturer" do
    sign_in users(:viewer)
    visit reports_path
    within "#sidebar" do
      assert_link "Reports"
      assert_no_link "Schedules"
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test:system test/system/reports_hub_test.rb -n "/sidebar shows one Reports/"`
Expected: FAIL — for a viewer the sidebar today has a "Schedules" link and no "Reports" link (Reports is admin-only).

- [ ] **Step 3: Add the top-level "Reports" nav item**

In `app/views/layouts/application.html.haml`, immediately **after** the Grades nav-item (the block ending with `Grades` at lines ~55–58) and **before** the Users nav-item, insert:

```haml
          %li.nav-item
            = link_to reports_path, class: "nav-link d-flex align-items-center #{'active' if controller_name.in?(%w[reports schedules])}" do
              = resource_icon("reports")
              Reports
```

(The `schedules` controller name is included so schedule reports still highlight the Reports item.)

- [ ] **Step 4: Remove the Teaching-section "Schedules" item**

In the same file, delete this block (Teaching section, lines ~78–81):

```haml
          %li.nav-item
            = link_to schedules_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'schedules'}" do
              = resource_icon("schedules")
              Schedules
```

- [ ] **Step 5: Remove the admin-section "Reports" item**

In the same file, inside the `- if current_user.admin?` block, delete this block (the first item after the "Admin" header, lines ~91–94):

```haml
            %li.nav-item
              = link_to reports_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'reports'}" do
                = resource_icon("reports")
                Reports
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test:system test/system/reports_hub_test.rb`
Expected: PASS (all four tests, including the new sidebar one).

- [ ] **Step 7: Commit**

```bash
hg commit app/views/layouts/application.html.haml test/system/reports_hub_test.rb -m "'Reports' in the sidebar was admin-only and hid the schedule reports elsewhere

A lecturer looking for a report saw either nothing (Reports was admin-gated) or
had to know timetable reports lived under 'Schedules' in the Teaching section.
Replace both with a single top-level 'Reports' item visible to every logged-in
user; Schedules is now a section inside the hub, one click away.

- Add top-level Reports nav item (active for reports + schedules controllers)
- Remove the Teaching-section Schedules item and the admin-section Reports item
- System test: sidebar has Reports, no separate Schedules, for a viewer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Schedules landing → redirect to the hub

**Files:**
- Modify: `app/controllers/schedules_controller.rb`
- Delete: `app/views/schedules/index.html.haml`
- Test: `test/controllers/schedules_controller_test.rb`, `test/system/schedules_test.rb`

**Interfaces:**
- Consumes: `reports_path`.
- Produces: nothing consumed by later tasks. Contextual deep-links to specific schedule reports (`schedules_teaching_matrix_path`, `schedules_conflicts_path`, etc.) and the reports' "Back" buttons (→ `schedules_path`) keep working; `schedules_path` now lands on the hub.

- [ ] **Step 1: Update the two failing tests first**

In `test/controllers/schedules_controller_test.rb`, replace the `"index is accessible"` test:

```ruby
  test "index redirects to the reports hub" do
    get schedules_path
    assert_redirected_to reports_path
  end
```

In `test/system/schedules_test.rb`, replace the `"landing page shows report cards"` test:

```ruby
  test "the schedules path redirects to the reports hub" do
    visit schedules_path
    assert_current_path reports_path
    assert_text "Schedules"        # now a hub section header
    assert_link "Room Schedule"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/schedules_controller_test.rb -n "/index redirects/"`
Expected: FAIL — `schedules#index` currently renders 200, not a redirect.

- [ ] **Step 3: Make `index` redirect**

In `app/controllers/schedules_controller.rb`, replace the `index` action body so it reads:

```ruby
  def index
    redirect_to reports_path
  end
```

(Keep the route `get "schedules", action: :index` — it backs `schedules_path`, used by every schedule report's "Back" button.)

- [ ] **Step 4: Delete the dead landing view**

```bash
hg remove app/views/schedules/index.html.haml
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/schedules_controller_test.rb`
Expected: PASS.

Run: `bin/rails test:system test/system/schedules_test.rb`
Expected: PASS (the redirect test plus the unchanged per-report calendar tests).

- [ ] **Step 6: Commit**

```bash
hg commit app/controllers/schedules_controller.rb app/views/schedules/index.html.haml test/controllers/schedules_controller_test.rb test/system/schedules_test.rb -m "Two report landing pages competed for the same job

The /schedules landing page was a second, parallel report hub. With the unified
hub live, point /schedules at it: the schedule reports now live as the hub's
Schedules and Teaching sections, and the reports' Back buttons (→ schedules_path)
land there too. One landing page, not two.

- schedules#index redirects to reports_path; delete the dead landing view
- Update schedules controller + system tests to assert the redirect

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Documentation

**Files:**
- Modify: `docs/backlog.md`
- Modify: `docs/schedule-reports.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the backlog overlap-review status**

In `docs/backlog.md`, under `## 2. Report ↔ entity page overlap review (recurring)`, add a status line dated 2026-07-19 recording the consolidation:

```markdown
- **2026-07-19 — two report hubs merged into one.** The admin-only `/reports`
  hub and the all-users `/schedules` hub are now a single lecturer-facing hub at
  `/reports`, driven by `Reports::Catalog`, gated per-report (only
  `data_coverage` is admin, and it renders outside the hub — linked from Data
  Sources). Report routes did not move, so entity→report cross-links (item 1)
  are unaffected. The "across a set" reports now all sit behind one door.
```

- [ ] **Step 2: Update the schedule-reports navigation note**

In `docs/schedule-reports.md`, under `## Sidebar Navigation`, replace the description of a dedicated "Schedules" sidebar entry + separate landing page with:

```markdown
As of 2026-07-19, schedule reports are surfaced through the unified report hub
(`/reports`, `Reports::Catalog`): the calendar reports (Room, Staff, Student,
Curriculum) plus Conflicts form the hub's **Schedules** section, and Workload +
Teaching Matrix form the **Teaching** section. There is no longer a separate
"Schedules" sidebar item or `/schedules` landing page — `schedules_path`
redirects to the hub. Each report keeps its own route and controller action.
```

- [ ] **Step 3: Commit**

```bash
hg commit docs/backlog.md docs/schedule-reports.md -m "Docs still described two separate report hubs after they were merged

Record the report-hub consolidation so a future session doesn't re-derive the
old two-hub layout from stale docs.

- backlog item 2: note the /reports + /schedules merge and per-report gating
- schedule-reports: replace the dedicated-Schedules-sidebar note with the hub

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Full test sweep**

Run: `bin/rails test && bin/rails test:system`
Expected: PASS. If anything else referenced the old `@reports_by_section`, `Reports::Registry.grouped` in a view, the `/schedules` landing, or the removed sidebar items, fix it in the same task and note it here.

---

## Self-Review

**1. Spec coverage** (against `docs/superpowers/specs/2026-07-19-report-hub-consolidation-design.md`):

- §1 Unified hub taxonomy (4 sections, Schedules/Teaching split, Conflicts under Schedules) → Task 1 (`Reports::Catalog` sections) + Task 3 (view). ✓
- §2 Access model (all hub reports `:all`; only `data_coverage` `:admin`; gating per-report) → Task 1 (entry access) + Task 2 (controller gate). ✓
- §3 Catalog architecture (one catalog; registry vs external; pages stay put) → Task 1 + Task 3 helper. ✓
- §4 Navigation (one "Reports" item; drop the two old items; `schedules/index` redirect) → Task 4 + Task 5. ✓
- §5 Data Coverage relocation (out of hub; Data Sources link pre-exists) → Task 1 (`:system`) + Task 3 (absent-from-hub test). The Data Sources page already links it (verified in `app/views/data_sources/index.html.haml`); no change needed there. ✓
- §6 Grade-distribution naming (distinct titles) → Task 1 (titles) + Task 1 test. ✓
- Entity-page embedding untouched → no task modifies show pages. ✓
- Backlog implications → Task 6. ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N"; every code step shows full content. ✓

**3. Type consistency:** `CatalogEntry` members (`key, title, description, section, access, path_helper, report_class`) and methods (`registry?`, `hub?`, `applicable_to?`) are used identically in Catalog (Task 1), controller (Task 2), and helper/view (Task 3). `@entries_by_section` produced in Task 2, consumed in Task 3. `catalog_report_path` defined in Task 3, used in the Task 3 view. ✓

**Note on Registry:** `Reports::Registry` and its test are intentionally left intact — Task 1's catalog test asserts the catalog covers `Reports::Registry.all`, so the two lists can't silently diverge.
