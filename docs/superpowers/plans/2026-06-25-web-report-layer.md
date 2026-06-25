# Web Report Layer + Per-Program FAQ Menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a web "Reports" section — a per-program menu of deterministic, staff-facing data reports — built on a shared `Reports::` query layer that returns pure Ruby data.

**Architecture:** Each report is a self-describing query object (`Reports::Base` subclass) with a small class-level DSL (`title/section/programs/param`) and a `#run` that returns a `Reports::Result` (columns + rows + summary). A `Reports::Registry` enumerates them for the per-program menu. `ReportsController` renders the dashboard (`index`) and a per-report param form + result table (`show`), with CSV export. The same query objects will later back a single enum-dispatched LINE tool (deferred — not in this plan).

**Tech Stack:** Ruby 3.4 / Rails 8.1, HAML, Bootstrap 5.3, DataTables (via `datatable` Stimulus controller), MySQL. VCS is **Mercurial (`hg`)**.

## Global Constraints

- **Tests are written AFTER implementation, not TDD** (project preference + `CLAUDE.md`). Implementation tasks (1–6) implement then commit; Task 7 is tests, gated on asking the user first per `CLAUDE.md`.
- **Intranet-only**: no CDN/external URLs. (No new assets here.)
- **VCS is `hg`, not git.** Commit with explicit file paths (`hg commit path1 path2 -m "..."`). Commit messages **lead with WHY** (first paragraph = motivation), then what.
- **Admin-only**: every report action is gated by `require_admin` (matches `/chat`).
- **Year fields are Buddhist Era (B.E.).** Report year params are B.E. (e.g. 2568).
- **Data-driven UI** (project convention): adding a report = add one class file + one line in `Reports::Registry::REPORTS`; no view edits.
- **`Reports::Base#run` returns pure data — never HTML, never prose.**

---

### Task 1: Reports foundation — `Result` + `Base`

**Files:**
- Create: `app/services/reports/result.rb`
- Create: `app/services/reports/base.rb`

**Interfaces:**
- Produces:
  - `Reports::Result.new(columns:, rows:, summary: nil)` — `columns` is `[{key: Symbol, label: String}]`, `rows` is `[Hash]` keyed by column key, `summary` is `String?`. Readers: `#columns`, `#rows`, `#summary`, `#empty?`.
  - `Reports::Base` class DSL: `.title(text=nil)`, `.section(sym=nil)`, `.programs(val=nil)` (default `:all`), `.param(name, type, required: false)`, `.params_spec` (`[{name:, type:, required:}]`), `.key` (demodulized underscore of class name), `.applicable_to?(program_group)`.
  - `Reports::Base` instance: `#initialize(params = {})`, `#run` (abstract — raises `NotImplementedError`), `#result(columns:, rows:, summary: nil)`, `#semester_scope`, plus a reader method per declared `param`.

- [ ] **Step 1: Create `Reports::Result`**

```ruby
# app/services/reports/result.rb
module Reports
  # Structured return value for every report. Both the web table renderer and
  # (future) the LINE JSON serializer consume this — never HTML, never prose.
  class Result
    attr_reader :columns, :rows, :summary

    # columns: [{ key: :student_id, label: "Student ID" }, ...]
    # rows:    [{ student_id: "65...", name: "...", ... }, ...]  (keyed by column key)
    # summary: short human sentence, or nil
    def initialize(columns:, rows:, summary: nil)
      @columns = columns
      @rows = rows
      @summary = summary
    end

    def empty?
      rows.empty?
    end
  end
end
```

- [ ] **Step 2: Create `Reports::Base`**

```ruby
# app/services/reports/base.rb
module Reports
  # Superclass for all reports. Provides a small class-level DSL so each report
  # is self-describing (drives both the menu and the param form), plus shared
  # instance helpers. Subclasses implement #run and return #result(...).
  class Base
    # ---- class-level DSL (plain class methods, like has_many/validates) ----
    def self.title(text = nil)
      text ? @title = text : @title
    end

    def self.section(sym = nil)
      sym ? @section = sym : @section
    end

    def self.programs(val = nil)
      val ? @programs = val : (@programs || :all)
    end

    def self.params_spec
      @params_spec ||= []
    end

    # Declares a parameter. Feeds the web form AND defines an instance reader.
    # type ∈ :course, :staff, :course_group, :academic_year, :integer, :term, :semester_record
    def self.param(name, type, required: false)
      params_spec << { name: name, type: type, required: required }
      define_method(name) { @params[name.to_s] }
    end

    # Stable identifier used in URLs and the registry, e.g. "failing_students".
    def self.key
      name.demodulize.underscore
    end

    # Should this report appear for the given ProgramGroup?
    def self.applicable_to?(program_group)
      programs == :all || Array(programs).include?(program_group.code.to_sym)
    end

    def initialize(params = {})
      @params = params.transform_keys(&:to_s)
    end

    def run
      raise NotImplementedError, "#{self.class}#run must be implemented"
    end

    private

    # Builds the structured result. Columns must be declared by the caller for
    # clean headers (we do not infer, to keep labels precise for staff).
    def result(columns:, rows:, summary: nil)
      Reports::Result.new(columns: columns, rows: rows, summary: summary)
    end

    # Resolves a :semester_record param (a Semester id) to a Semester, defaulting
    # to the latest term when blank. Used by offering-based reports.
    def semester_scope
      sem_id = @params["semester"]
      sem_id.present? ? Semester.find_by(id: sem_id) : Semester.ordered.first
    end
  end
end
```

- [ ] **Step 3: Verify the classes autoload**

Run: `bin/rails zeitwerk:check`
Expected: `All is good!` (no autoload errors).

Run: `bin/rails runner 'puts Reports::Result.new(columns: [], rows: []).empty?'`
Expected: `true`

- [ ] **Step 4: Commit**

```bash
hg add app/services/reports/result.rb app/services/reports/base.rb
hg commit app/services/reports/result.rb app/services/reports/base.rb \
  -m "Add Reports foundation so web and LINE can share one query layer

Staff data questions are currently only answerable via the LINE LLM bot;
we want them on the web too, without duplicating query logic. Reports::Base
gives each report a self-describing DSL and a pure-data #result, so one
query object can feed both a web table and (later) a LINE tool.

- Reports::Result: columns/rows/summary value object
- Reports::Base: title/section/programs/param DSL, key, applicable_to?,
  semester_scope helper"
```

---

### Task 2: The five report query objects

**Files:**
- Create: `app/services/reports/course_teachers.rb`
- Create: `app/services/reports/failing_students.rb`
- Create: `app/services/reports/group_credit_shortfall.rb`
- Create: `app/services/reports/thesis_credits.rb`
- Create: `app/services/reports/staff_courses_by_year.rb`

**Interfaces:**
- Consumes: `Reports::Base` DSL + `#result` + `#semester_scope` (Task 1).
- Consumes (models): `Grade` (`belongs_to :student, :course`; scope `graded` = grade_weight not nil; columns `grade`, `credits_grant`, `year`, `semester`), `Course` (`course_no`, `name`, `course_group`, `is_thesis`), `CourseOffering` (`belongs_to :course, :semester`; `has_many :sections`), `Section` (`section_number`; `has_many :teachings`), `Teaching` (`belongs_to :section, :staff`), `Staff` (`display_name_th`, `initials`, name fields), `Student` (`student_id`, `display_name`, `admission_year_be`, `status`), `Semester` (`year_be`, scope `ordered`, `display_name`).
- Produces: each class `Reports::X` with `.key`, `.title`, `.section`, `.programs`, `.params_spec`, and `#run -> Reports::Result`.

- [ ] **Step 1: `CourseTeachers`**

```ruby
# app/services/reports/course_teachers.rb
module Reports
  # "Who teaches this subject?" — instructors of a course's sections in a term.
  class CourseTeachers < Base
    title    "Who teaches this subject"
    section  :courses
    programs :all
    param    :course_no, :course,          required: true
    param    :semester,  :semester_record               # optional; defaults to latest

    def run
      sem = semester_scope
      offerings = CourseOffering.joins(:course)
                                .where(courses: { course_no: course_no })
      offerings = offerings.where(semester_id: sem.id) if sem
      offerings = offerings.includes(:course, :semester, sections: { teachings: :staff })

      rows = []
      offerings.each do |off|
        off.sections.each do |sec|
          sec.teachings.each do |t|
            rows << { course_no: off.course.course_no, name: off.course.name,
                      section: sec.section_number, instructor: t.staff.display_name_th,
                      term: off.semester.display_name }
          end
        end
      end

      result(
        columns: [ { key: :course_no, label: "Course No" }, { key: :name, label: "Course" },
                   { key: :section, label: "Section" }, { key: :instructor, label: "Instructor" },
                   { key: :term, label: "Term" } ],
        rows: rows,
        summary: "#{rows.size} teaching assignment(s) for #{course_no}#{" in #{sem.display_name}" if sem}"
      )
    end
  end
end
```

- [ ] **Step 2: `FailingStudents`**

```ruby
# app/services/reports/failing_students.rb
module Reports
  # "Which students failed this subject?" — grade F in a course for a term.
  class FailingStudents < Base
    title    "Which students failed this subject"
    section  :courses
    programs :all
    param    :course_no, :course,        required: true
    param    :year,      :academic_year, required: true   # B.E. year of the grade
    param    :term,      :term                            # optional 1/2/3

    def run
      scope = Grade.graded.joins(:course, :student)
                   .where(courses: { course_no: course_no }, grade: "F", year: year)
      scope = scope.where(semester: term) if term.present?

      rows = scope.map do |g|
        { student_id: g.student.student_id, name: g.student.display_name,
          term: "#{g.year}/#{g.semester}", grade: g.grade }
      end

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :term, label: "Term" }, { key: :grade, label: "Grade" } ],
        rows: rows,
        summary: "#{rows.size} student(s) failed #{course_no} in #{year}"
      )
    end
  end
end
```

- [ ] **Step 3: `GroupCreditShortfall`**

```ruby
# app/services/reports/group_credit_shortfall.rb
module Reports
  # "Who hasn't earned enough credits in this course group?" — threshold typed
  # by staff for v1 (CurriculumRequirement model is a follow-on spec).
  class GroupCreditShortfall < Base
    title    "Who lacks enough credits in a course group"
    section  :curriculum
    programs :all
    param    :course_group,     :course_group,  required: true
    param    :required_credits, :integer,       required: true
    param    :admission_year,   :academic_year                 # optional cohort filter

    def run
      threshold = required_credits.to_i

      students = Student.all
      students = students.where(admission_year_be: admission_year) if admission_year.present?

      # earned credits per student within the group (SUM ignores NULL credits_grant)
      earned = Grade.graded.joins(:course)
                    .where(courses: { course_group: course_group })
                    .group(:student_id).sum(:credits_grant)

      rows = students.filter_map do |s|
        got = earned[s.id] || 0
        next if got >= threshold
        { student_id: s.student_id, name: s.display_name, earned: got,
          required: threshold, missing: threshold - got }
      end.sort_by { |r| -r[:missing] }

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :earned, label: "Earned" }, { key: :required, label: "Required" },
                   { key: :missing, label: "Missing" } ],
        rows: rows,
        summary: "#{rows.size} student(s) below #{threshold} credits in '#{course_group}'"
      )
    end
  end
end
```

- [ ] **Step 4: `ThesisCredits`**

```ruby
# app/services/reports/thesis_credits.rb
module Reports
  # "How many thesis credits has each student enrolled?" — master programs only.
  class ThesisCredits < Base
    title    "Thesis credits per student"
    section  :thesis
    programs [ :CM, :CS, :SE ]                       # master groups only
    param    :admission_year, :academic_year         # optional cohort filter

    def run
      thesis_credits = Grade.graded.joins(:course)
                            .where(courses: { is_thesis: true })
                            .group(:student_id).sum(:credits_grant)

      students = Student.where(id: thesis_credits.keys)
      students = students.where(admission_year_be: admission_year) if admission_year.present?

      rows = students.map do |s|
        { student_id: s.student_id, name: s.display_name,
          thesis_credits: thesis_credits[s.id] || 0 }
      end.sort_by { |r| -r[:thesis_credits] }

      result(
        columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" },
                   { key: :thesis_credits, label: "Thesis Credits" } ],
        rows: rows,
        summary: "#{rows.size} student(s) with thesis credits"
      )
    end
  end
end
```

- [ ] **Step 5: `StaffCoursesByYear`**

```ruby
# app/services/reports/staff_courses_by_year.rb
module Reports
  # "Which courses did X teach in a given year?" — by staff initials or name.
  class StaffCoursesByYear < Base
    title    "Courses taught by a staff member in a year"
    section  :courses
    programs :all
    param    :staff, :staff,         required: true   # initials (e.g. NNN) or name
    param    :year,  :academic_year, required: true   # B.E. year of the offering's term

    def run
      person = find_staff
      cols = [ { key: :course_no, label: "Course No" }, { key: :name, label: "Course" },
               { key: :section, label: "Section" }, { key: :term, label: "Term" } ]
      return result(columns: cols, rows: [], summary: "No staff matched '#{staff}'") unless person

      teachings = Teaching.where(staff_id: person.id)
                          .joins(section: { course_offering: [ :course, :semester ] })
                          .where(semesters: { year_be: year })
                          .includes(section: { course_offering: [ :course, :semester ] })

      rows = teachings.map do |t|
        co = t.section.course_offering
        { course_no: co.course.course_no, name: co.course.name,
          section: t.section.section_number, term: co.semester.display_name }
      end.uniq

      result(columns: cols, rows: rows,
             summary: "#{rows.size} course(s) taught by #{person.display_name_th} in #{year}")
    end

    private

    def find_staff
      q = staff.to_s.strip
      if q.match?(/\A[A-Za-z]{2,4}\z/)
        Staff.find_by(initials: q.upcase)
      else
        like = "%#{q}%"
        Staff.where("first_name LIKE :q OR last_name LIKE :q OR " \
                    "first_name_th LIKE :q OR last_name_th LIKE :q", q: like).first
      end
    end
  end
end
```

- [ ] **Step 6: Verify the reports autoload and expose metadata**

Run: `bin/rails zeitwerk:check`
Expected: `All is good!`

Run:
```bash
bin/rails runner 'puts [Reports::CourseTeachers, Reports::FailingStudents, Reports::GroupCreditShortfall, Reports::ThesisCredits, Reports::StaffCoursesByYear].map { |r| "#{r.key} / #{r.title} / #{r.section} / #{r.programs.inspect}" }'
```
Expected (5 lines), e.g.:
```
course_teachers / Who teaches this subject / courses / :all
failing_students / Which students failed this subject / courses / :all
group_credit_shortfall / Who lacks enough credits in a course group / curriculum / :all
thesis_credits / Thesis credits per student / thesis / [:CM, :CS, :SE]
staff_courses_by_year / Courses taught by a staff member in a year / courses / :all
```

- [ ] **Step 7: Commit**

```bash
hg add app/services/reports/course_teachers.rb app/services/reports/failing_students.rb app/services/reports/group_credit_shortfall.rb app/services/reports/thesis_credits.rb app/services/reports/staff_courses_by_year.rb
hg commit app/services/reports/course_teachers.rb app/services/reports/failing_students.rb app/services/reports/group_credit_shortfall.rb app/services/reports/thesis_credits.rb app/services/reports/staff_courses_by_year.rb \
  -m "Add the five transcript-side reports staff asked for

These answer the questions staff currently ask the LINE bot (who teaches X,
who failed X, who lacks credits in a group, thesis credits, what X taught)
as deterministic queries over existing transcript/offering data — no LLM,
no curriculum-requirements model (that threshold is a typed param for now).

- CourseTeachers, FailingStudents, GroupCreditShortfall, ThesisCredits,
  StaffCoursesByYear, each a Reports::Base subclass returning pure data"
```

---

### Task 3: `Reports::Registry`

**Files:**
- Create: `app/services/reports/registry.rb`

**Interfaces:**
- Consumes: the five report classes (Task 2), `ProgramGroup` (`code`).
- Produces: `Reports::Registry::SECTIONS` (`{Symbol => String}`), `.all`, `.find(key) -> Class?`, `.for_program(program_group) -> [Class]`, `.grouped(reports = all) -> {section_sym => [Class]}`.

> Note: we list reports in an explicit `REPORTS` constant rather than auto-discovering subclasses — reliable under Rails dev-mode autoloading. Adding a report = its class file + one line here.

- [ ] **Step 1: Create the registry**

```ruby
# app/services/reports/registry.rb
module Reports
  # Single source of truth for which reports exist and how the menu groups them.
  module Registry
    # Display order + labels for menu sections.
    SECTIONS = {
      courses:    "Courses",
      students:   "Students",
      curriculum: "Curriculum",
      thesis:     "Thesis"
    }.freeze

    # Add a new report here (one line) after creating its class file.
    REPORTS = [
      Reports::CourseTeachers,
      Reports::FailingStudents,
      Reports::GroupCreditShortfall,
      Reports::ThesisCredits,
      Reports::StaffCoursesByYear
    ].freeze

    def self.all
      REPORTS
    end

    def self.find(key)
      REPORTS.find { |r| r.key == key }
    end

    def self.for_program(program_group)
      REPORTS.select { |r| r.applicable_to?(program_group) }
    end

    # Groups by section in SECTIONS order; only sections that have reports appear.
    def self.grouped(reports = all)
      reports.group_by(&:section)
             .sort_by { |section, _| SECTIONS.keys.index(section) || Float::INFINITY }
             .to_h
    end
  end
end
```

- [ ] **Step 2: Verify**

Run: `bin/rails zeitwerk:check` → `All is good!`

Run: `bin/rails runner 'p Reports::Registry.all.map(&:key); p Reports::Registry.grouped.transform_values { |v| v.map(&:key) }'`
Expected:
```
["course_teachers", "failing_students", "group_credit_shortfall", "thesis_credits", "staff_courses_by_year"]
{:courses=>["course_teachers", "failing_students", "staff_courses_by_year"], :curriculum=>["group_credit_shortfall"], :thesis=>["thesis_credits"]}
```

- [ ] **Step 3: Commit**

```bash
hg add app/services/reports/registry.rb
hg commit app/services/reports/registry.rb \
  -m "Add Reports::Registry so the menu is data-driven

The per-program report menu must filter by program and group by section
without per-page if/else. The registry centralizes the report list, section
labels, and program filtering so adding a report stays a one-line change.

- SECTIONS labels, REPORTS list, .all/.find/.for_program/.grouped"
```

---

### Task 4: Routes, `ReportsController`, icon + sidebar nav

**Files:**
- Modify: `config/routes.rb` (add after the `resource :chat` line, ~line 63)
- Create: `app/controllers/reports_controller.rb`
- Modify: `app/helpers/application_helper.rb` (add to `RESOURCE_ICONS`, ~line 21)
- Modify: `app/views/layouts/application.html.haml` (add a nav `%li.nav-item`, after the `schedules` item ~line 80)

**Interfaces:**
- Consumes: `Reports::Registry` (Task 3), `ProgramGroup` (`order(:code)`, `find_by(code:)`), `Exporters::ReportExporter` (Task 6 — only used by the `format.csv` branch; Task 6 creates it, so CSV download is exercised after Task 6).
- Produces: routes `reports_path`, `report_path(key)`; `@report`, `@result`, `@reports_by_section`, `@program_groups`, `@selected_group` for views; `RESOURCE_ICONS["reports"]`.

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, immediately after `resource :chat, only: [:show, :create]`:

```ruby
  resources :reports, only: [:index, :show]
```

- [ ] **Step 2: Create the controller**

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  before_action :require_admin

  # Dashboard: per-program menu of reports, grouped by section.
  def index
    @program_groups = ProgramGroup.order(:code)
    @selected_group = @program_groups.find_by(code: params[:program_group]) if params[:program_group].present?
    reports = @selected_group ? Reports::Registry.for_program(@selected_group) : Reports::Registry.all
    @reports_by_section = Reports::Registry.grouped(reports)
  end

  # One report: render its param form, and (when run) its result table / CSV.
  def show
    @report = Reports::Registry.find(params[:id])
    return redirect_to(reports_path, alert: "Unknown report.") unless @report

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

  def require_admin
    redirect_to root_path, alert: "Only admins can view reports." unless current_user.admin?
  end
end
```

- [ ] **Step 3: Add the resource icon**

In `app/helpers/application_helper.rb`, add inside the `RESOURCE_ICONS` hash (before the closing `}.freeze`):

```ruby
    "reports"          => "query_stats",
```

- [ ] **Step 4: Add the sidebar nav link**

In `app/views/layouts/application.html.haml`, after the `schedules` `%li.nav-item` block (the one ending with `resource_icon("schedules")` + label, ~line 80), add:

```haml
          %li.nav-item
            = link_to reports_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'reports'}" do
              = resource_icon("reports")
              Reports
```

(Match the exact indentation of the surrounding `%li.nav-item` blocks — they sit under `%ul.nav.nav-pills`.)

- [ ] **Step 5: Verify routes + auth (views land in Task 5/6, so `index` will error until then — check routing only here)**

Run: `bin/rails routes -g report`
Expected: includes `reports GET /reports(.:format) reports#index` and `report GET /reports/:id(.:format) reports#show`.

Run: `bin/rails zeitwerk:check` → `All is good!`

- [ ] **Step 6: Commit**

```bash
hg add app/controllers/reports_controller.rb
hg commit config/routes.rb app/controllers/reports_controller.rb app/helpers/application_helper.rb app/views/layouts/application.html.haml \
  -m "Wire up Reports routes, controller, and nav entry

Staff need a discoverable home for the new reports. ReportsController turns
the data-driven registry into an admin-only dashboard + per-report run page,
reachable from the sidebar.

- resources :reports (index, show); admin gate
- index groups reports by section, filters by selected program
- show validates required params, runs the report, supports CSV format
- reports icon + sidebar nav link"
```

---

### Task 5: Dashboard view (`index`)

**Files:**
- Create: `app/views/reports/index.html.haml`

**Interfaces:**
- Consumes: `@program_groups`, `@selected_group`, `@reports_by_section` (Task 4); `Reports::Registry::SECTIONS`; `report.key`, `report.title`; `report_path`, `reports_path`.

- [ ] **Step 1: Create the dashboard**

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

    - if @reports_by_section.empty?
      %p.text-body-secondary.mb-0 No reports for this program.
    - @reports_by_section.each do |section_key, reports|
      .mb-4
        %h6.text-uppercase.text-body-secondary.small.fw-semibold.mb-2= Reports::Registry::SECTIONS[section_key]
        .row.g-3
          - reports.each do |report|
            .col-md-4
              = link_to report_path(report.key), class: "card h-100 text-decoration-none" do
                .card-body
                  %h6.card-title.mb-1= report.title
                  %p.small.text-body-secondary.mb-0= report.key.humanize
```

- [ ] **Step 2: Verify in the app**

Start the server (`bin/dev`), log in as an admin, visit `/reports`.
Expected: a "Reports" card with a Program dropdown + Apply; report cards under "Courses", "Curriculum", "Thesis". Selecting `CP` + Apply hides the Thesis card; selecting `CM` + Apply shows it.

- [ ] **Step 3: Commit**

```bash
hg add app/views/reports/index.html.haml
hg commit app/views/reports/index.html.haml \
  -m "Add reports dashboard with per-program filtering

Staff need to find the right report quickly and only see ones relevant to a
program. The dashboard renders the registry grouped by section with a program
selector that filters the menu (e.g. Thesis only shows for master programs)."
```

---

### Task 6: Report run page (`show`) — form, result table, CSV export

**Files:**
- Create: `app/services/exporters/report_exporter.rb`
- Create: `app/views/reports/show.html.haml`
- Create: `app/views/reports/_form.html.haml`
- Create: `app/views/reports/_result_table.html.haml`

**Interfaces:**
- Consumes: `@report` (class), `@result` (`Reports::Result`) from Task 4; `Semester.ordered`, `Semester#display_name`; `chat_path`; `report_path`.
- Produces: `Exporters::ReportExporter.new(result, filename:)` with `#to_csv` and `#filename`.

- [ ] **Step 1: Create the CSV exporter**

```ruby
# app/services/exporters/report_exporter.rb
require "csv"

module Exporters
  # Turns any Reports::Result into a CSV download (columns -> header row).
  class ReportExporter
    def initialize(result, filename: "report")
      @result = result
      @name = filename
    end

    def to_csv
      CSV.generate do |csv|
        csv << @result.columns.map { |c| c[:label] }
        @result.rows.each { |row| csv << @result.columns.map { |c| row[c[:key]] } }
      end
    end

    def filename
      "#{@name}.csv"
    end
  end
end
```

- [ ] **Step 2: Create the show page**

```haml
-# app/views/reports/show.html.haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1.h4.mb-0= @report.title
  = link_to "Back", reports_path, class: "btn btn-outline-primary btn-sm"

.card.mb-3
  .card-body
    = render "form"

- if @result
  = render "result_table"
```

- [ ] **Step 3: Create the param form partial**

```haml
-# app/views/reports/_form.html.haml
-# Built from @report.params_spec — input widget chosen by param :type.
= form_with url: report_path(@report.key), method: :get, class: "row g-3 align-items-end" do
  = hidden_field_tag :run, 1
  - @report.params_spec.each do |p|
    .col-md-3
      = label_tag p[:name], p[:name].to_s.humanize, class: "form-label small text-muted"
      - case p[:type]
      - when :term
        = select_tag p[:name], options_for_select([["First", 1], ["Second", 2], ["Summer", 3]], params[p[:name]]), include_blank: true, class: "form-select"
      - when :semester_record
        = select_tag p[:name], options_for_select(Semester.ordered.map { |s| [s.display_name, s.id] }, params[p[:name]]), include_blank: true, class: "form-select"
      - when :academic_year, :integer
        = number_field_tag p[:name], params[p[:name]], class: "form-control"
      - else
        = text_field_tag p[:name], params[p[:name]], class: "form-control"
  .col-md-3
    = submit_tag "Run report", class: "btn btn-primary"
```

- [ ] **Step 4: Create the result table partial**

```haml
-# app/views/reports/_result_table.html.haml
- if @result.summary
  %p.text-body-secondary= @result.summary

.card{"data-controller" => "datatable"}
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h6.card-title.mb-0 Results
      .d-flex.gap-2
        = link_to report_path(@report.key, request.query_parameters.merge(format: :csv)), class: "btn btn-outline-secondary btn-sm" do
          %span.material-symbols{style: "font-size: 16px; vertical-align: middle;"} download
          Export CSV
        = link_to chat_path, class: "btn btn-outline-secondary btn-sm" do
          %span.material-symbols{style: "font-size: 16px; vertical-align: middle;"} forum
          Ask a follow-up
    .table-responsive
      %table.table.table-hover.mb-0{"data-datatable-target" => "table"}
        %thead
          %tr
            - @result.columns.each do |col|
              %th= col[:label]
        %tbody
          - @result.rows.each do |row|
            %tr
              - @result.columns.each do |col|
                %td= row[col[:key]]
```

- [ ] **Step 5: Verify end-to-end in the app**

With `bin/dev` running, logged in as admin:
- Visit `/reports`, click **Which students failed this subject**.
- Fill `Course no` (a real `course_no` with grades), `Year` (B.E. with data), click **Run report**.
- Expected: summary line + a DataTable of failing students; **Export CSV** downloads `failing_students.csv` with matching rows; **Ask a follow-up** links to `/chat`.
- Visit a report with no required params (**Thesis credits per student**), pick `CM` from the dashboard first; run it.
- Submit a required-param report with a blank required field → expect the "Please fill in: …" alert, no table.

- [ ] **Step 6: Commit**

```bash
hg add app/services/exporters/report_exporter.rb app/views/reports/show.html.haml app/views/reports/_form.html.haml app/views/reports/_result_table.html.haml
hg commit app/services/exporters/report_exporter.rb app/views/reports/show.html.haml app/views/reports/_form.html.haml app/views/reports/_result_table.html.haml \
  -m "Render report param form, result table, and CSV export

Completes the web report surface: staff pick a report, fill parameters
(widget chosen from the param type), and get a sortable DataTable they can
export to CSV or follow up on in chat. The form/table are generic — driven
by the report's declared params and Result columns, so new reports need no
view code."
```

---

### Task 7: Tests  — CHECKPOINT (ask the user first)

> Per `CLAUDE.md` ("After implementing a feature: ask whether to write tests") and the user's
> tests-after preference: **before writing these, ask the user whether to proceed, and briefly
> confirm what to cover.** Do not auto-run this task as part of the implementation sweep.

**Files:**
- Create: `test/services/reports/failing_students_test.rb`
- Create: `test/services/reports/group_credit_shortfall_test.rb`
- Create: `test/services/reports/thesis_credits_test.rb`
- Create: `test/services/reports/registry_test.rb`
- Create: `test/system/reports_test.rb`
- Possibly modify: fixtures under `test/fixtures/` (grades, courses, students, semesters, sections, teachings) to give reports deterministic data.

**Interfaces:**
- Consumes: existing fixtures; `Reports::*`, `Reports::Registry`; login helper pattern from `docs/code-patterns.md`.

- [ ] **Step 1: Confirm scope with the user**, then check existing fixtures:

Run: `ls test/fixtures` and inspect `grades.yml`, `courses.yml`, `students.yml` to see what data exists before adding report-specific fixtures.

- [ ] **Step 2: Unit test — `FailingStudents` returns only F grades for the term**

```ruby
# test/services/reports/failing_students_test.rb
require "test_helper"

class Reports::FailingStudentsTest < ActiveSupport::TestCase
  test "returns students with grade F for the given course and year" do
    result = Reports::FailingStudents.new(
      "course_no" => courses(:algorithms).course_no, "year" => grades(:algo_fail).year
    ).run

    ids = result.rows.map { |r| r[:student_id] }
    assert_includes ids, students(:failing_one).student_id
    assert_not_includes ids, students(:passing_one).student_id
    assert_equal "Student ID", result.columns.first[:label]
  end

  test "empty result is not an error" do
    result = Reports::FailingStudents.new("course_no" => "0000000", "year" => 2568).run
    assert result.empty?
    assert_match(/0 student/, result.summary)
  end
end
```

> NOTE: fixture names (`courses(:algorithms)`, `grades(:algo_fail)`, `students(:failing_one)`,
> `students(:passing_one)`) must exist — add them in Step 1 if missing. Do not reference
> fixtures that aren't defined.

- [ ] **Step 3: Unit test — `GroupCreditShortfall` lists only students under threshold** (write analogous to Step 2 using a known `course_group` and `required_credits`; assert a below-threshold student appears with correct `missing`, an at/above-threshold student does not).

- [ ] **Step 4: Unit test — `ThesisCredits` sums thesis-course credits and only lists students with any** (assert a student with thesis grades appears with summed `thesis_credits`; a non-thesis student does not).

- [ ] **Step 5: Unit test — `Registry`** (assert `for_program` hides `ThesisCredits` for a bachelor `ProgramGroup` and includes it for a master group; `find("failing_students")` returns the class; `grouped` keys follow `SECTIONS` order).

- [ ] **Step 6: System test — dashboard + run one report** (login as admin via the `docs/code-patterns.md` system-test pattern; visit `/reports`; click a report; fill params; assert the summary and a known student row render; assert an empty run shows the summary, not a crash).

- [ ] **Step 7: Run the tests**

Run: `bin/rails test test/services/reports`
Expected: all green.

Run: `bin/rails test:system TEST=test/system/reports_test.rb`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
hg add test/services/reports test/system/reports_test.rb
hg commit <explicit test files + any changed fixtures> \
  -m "Test the report query objects and dashboard

Locks in the report query behavior (failing filter, credit-shortfall
threshold, thesis sum, registry program filtering) and the admin dashboard
happy path + empty-result case, so future reports can't silently regress
the shared layer."
```

---

## Post-implementation cleanup (when the feature is merged)

Per the spec's lifecycle note, once shipped:
- Distill any durable conventions (the `Reports::` layer, the registry pattern) into `CLAUDE.md`.
- Delete this plan and the spec (`docs/superpowers/specs/2026-06-25-web-report-layer-design.md`,
  `docs/superpowers/plans/2026-06-25-web-report-layer.md`) — history retains the rationale.

## Deferred to follow-on specs (NOT in this plan)

- LINE `report_query` tool (single enum-dispatched tool over `Reports::Registry`).
- `CurriculumRequirement` model + seeds (replaces the typed `required_credits` param).
- Full per-student degree-audit / progress view.
- Migrating existing LINE lookup tools onto the `Reports::` layer.
- Select2 enhancement of the param form's course/staff inputs; `U`-grade handling in `FailingStudents`.
