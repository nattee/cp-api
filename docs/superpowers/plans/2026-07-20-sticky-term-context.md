# Sticky Term Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user set their working academic term once and have every relevant report form arrive pre-filled with it, without ever changing what a report computes.

**Architecture:** One `TermContext` value object resolves the term from the session (falling back to the latest semester). Two read-paths consume it: an explicit per-field opt-in on the `Reports::Base` param DSL for hub reports, and a fallback in the hand-rolled schedule views/controller. A context bar on report pages writes the session.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, HAML, Stimulus, Bootstrap 5.3, Minitest + fixtures, Capybara + Selenium (headless Firefox), Mercurial.

## Global Constraints

- **Version control is Mercurial (`hg`), not git.** There is no `.git` directory. `git` commands fail.
- **`hg commit` must always name explicit files.** The repo may carry unrelated dirty changes. Never a bare `hg commit`.
- **Commit messages lead with WHY.** First paragraph = the problem/motivation; bullets = what changed.
- **Defaults only.** The context pre-fills form fields. It must never change what a report computes, and a report must never write back to the context.
- **The cohort trap.** `admission_year` (Cohort GPA, Group Credit Shortfall, Thesis Credits) is a cohort identity, not a viewing term, and shares the `:academic_year` param type with viewing-year fields. Opt-in is therefore **per field and explicit** — these three reports must never be filled from context. A test must prove it.
- **Range reports abstain.** Staff Workload and Class Grade Distribution (grades#distribution) ignore the context.
- **Intranet-only.** No CDN links, no external URLs.
- **Do not run the full `bin/rails test` suite inside a task.** Run only the test files the task names. For system tests use `bin/rails test <path>` — **`bin/rails test:system <path>` ignores its path arguments in this Rails version and runs all 107 system tests.** The controller runs the full suite once at the end.
- **Stimulus controllers auto-register** via `eagerLoadControllersFrom` — a new file in `app/javascript/controllers/` needs no manual registration.
- **Fixture fact:** `Semester.ordered.first` over the test fixtures is `sem_2568_2` (year_be 2568, semester_number 2). So the *default* `TermContext` in tests is academic_year_be **2568**, semester_number **2**.

---

## File Structure

**Created:**
- `app/services/term_context.rb` — the value object: resolves session → (year, semester), projects to year / semester_number / Semester record.
- `app/controllers/term_contexts_controller.rb` — `#update` writes the session pair, redirects back.
- `app/views/shared/_term_context_bar.html.haml` — the two-dropdown control.
- `app/javascript/controllers/term_context_controller.js` — submit-on-change.
- Test files (one per task, listed in each task).

**Modified:**
- `config/routes.rb` — `resource :term_context, only: :update`
- `app/controllers/application_controller.rb` — `current_term_context` helper + `helper_method`
- `app/services/reports/base.rb` — `param` accepts `context:`
- `app/helpers/reports_helper.rb` — `context_default_for(param)`
- `app/views/reports/_form.html.haml` — pre-fill each field from context
- `app/services/reports/semester_grade_distribution.rb`, `failing_students.rb`, `staff_courses_by_year.rb` — add `context:` to viewing-term params
- `app/controllers/schedules_controller.rb` — teaching-matrix defaults from context
- `app/views/schedules/{room,staff,student,curriculum,conflicts}.html.haml` — semester preselect from context; render the bar
- `app/views/schedules/teaching_matrix.html.haml` — render the bar
- `app/views/reports/index.html.haml`, `app/views/reports/show.html.haml` — render the bar

**Deliberately untouched:** the sidebar; the three cohort reports; `app/views/schedules/workload.html.haml` and `app/views/grades/` (the two range pages — no bar, no pre-fill); `Reports::Catalog`; every report's `#run`.

**A refinement of the spec, made explicit here:** the spec says "render the bar on each registry report's show page." Rendering it on a *non-consuming* registry report (a cohort report) would imply it filters that report, which it does not. So `reports/show.html.haml` renders the bar **only when the report has at least one context-opted param** (`@report.params_spec.any? { |p| p[:context] }`). This is data-driven — no report names hardcoded — and keeps the bar off the cohort reports automatically.

---

### Task 1: `TermContext` value object

**Files:**
- Create: `app/services/term_context.rb`
- Test: `test/services/term_context_test.rb`

**Interfaces:**
- Consumes: `Semester` (`ordered` scope, `year_be`, `semester_number`).
- Produces: `TermContext.from_session(session) → TermContext`; `TermContext.default → TermContext`; instances respond to `academic_year_be` (Integer|nil), `semester_number` (Integer|nil), `semester_record` (Semester|nil), `present?` (Boolean). Session shape it reads: `session[:term_context] = { "year_be" => Integer, "semester" => Integer|nil }`.

- [ ] **Step 1: Write the failing test**

Create `test/services/term_context_test.rb`:

```ruby
require "test_helper"

class TermContextTest < ActiveSupport::TestCase
  test "default resolves to the latest semester" do
    ctx = TermContext.default
    assert_equal 2568, ctx.academic_year_be
    assert_equal 2, ctx.semester_number   # sem_2568_2 is Semester.ordered.first
  end

  test "a stored pair is used when its year exists" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => 1 } })
    assert_equal 2567, ctx.academic_year_be
    assert_equal 1, ctx.semester_number
  end

  test "a stored whole-year value has a nil semester" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => nil } })
    assert_equal 2567, ctx.academic_year_be
    assert_nil ctx.semester_number
  end

  test "a stored year no longer in the data falls back to the default" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 1999, "semester" => 1 } })
    assert_equal 2568, ctx.academic_year_be   # default, not 1999
  end

  test "no stored value falls back to the default" do
    ctx = TermContext.from_session({})
    assert_equal 2568, ctx.academic_year_be
  end

  test "semester_record resolves the matching row" do
    ctx = TermContext.from_session({ term_context: { "year_be" => 2567, "semester" => 2 } })
    assert_equal semesters(:sem_2567_2), ctx.semester_record
  end

  test "semester_record is nil when no row matches the pair" do
    # 2568 exists but there is no summer (semester 3) fixture for it
    ctx = TermContext.from_session({ term_context: { "year_be" => 2568, "semester" => 3 } })
    assert_nil ctx.semester_record
    assert_equal 2568, ctx.academic_year_be   # year-level use still works
  end

  test "present? is false only when there are no semesters at all" do
    assert TermContext.default.present?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/term_context_test.rb`
Expected: FAIL — `NameError: uninitialized constant TermContext`

- [ ] **Step 3: Write the implementation**

Create `app/services/term_context.rb`:

```ruby
# The user's current working term, as a value object. Resolves from the session
# and, when unset or stale, from the latest semester on record. It only ever
# supplies DEFAULTS to report forms — it never changes what a report computes.
#
# The canonical unit is (academic_year_be, semester_number), matching how the app
# stores a Thai academic year (year_be) rather than a calendar year. semester_number
# may be nil, meaning "whole year". The pair is stored, not a Semester#id, so a
# year-level report works even when that specific semester row does not exist.
class TermContext
  attr_reader :academic_year_be, :semester_number

  def self.from_session(session)
    stored = session[:term_context]
    year = stored && stored["year_be"]
    if year.present? && Semester.exists?(year_be: year)
      new(academic_year_be: year.to_i, semester_number: stored["semester"]&.to_i)
    else
      default
    end
  end

  def self.default
    latest = Semester.ordered.first
    new(academic_year_be: latest&.year_be, semester_number: latest&.semester_number)
  end

  def initialize(academic_year_be:, semester_number:)
    @academic_year_be = academic_year_be
    @semester_number = semester_number
  end

  # The Semester row for this exact pair, or nil if none exists (e.g. a summer
  # that was never created). Callers treat nil as "unspecified".
  def semester_record
    return nil unless academic_year_be && semester_number
    Semester.find_by(year_be: academic_year_be, semester_number: semester_number)
  end

  def present?
    academic_year_be.present?
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/term_context_test.rb`
Expected: PASS — 8 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
hg add app/services/term_context.rb test/services/term_context_test.rb
hg commit app/services/term_context.rb test/services/term_context_test.rb -m "Reports have no shared notion of the term the user is working in

Part 3 needs one authoritative answer to 'which term?' that every report can
read the same way. The reports themselves express a term five different ways, so
the shared piece has to be a single canonical unit they all translate from.

- Add TermContext: resolves (academic_year_be, semester_number) from the session,
  falling back to the latest semester when unset or stale
- Stores the year+semester pair, not a Semester id, so a year-level report works
  in a year whose specific semester row does not exist, and a deleted row cannot
  dangle
- semester_record returns nil rather than raising when no row matches the pair

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Reading and writing the context (`current_term_context` + `TermContextsController`)

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/term_contexts_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/term_contexts_controller_test.rb`

**Interfaces:**
- Consumes: `TermContext.from_session` (Task 1).
- Produces: `ApplicationController#current_term_context → TermContext` (memoized, also a `helper_method` so views and helpers can call it). Route `term_context_path` (PATCH). `TermContextsController#update` reads `params[:year_be]` and `params[:semester]`, writes `session[:term_context] = { "year_be" => Integer, "semester" => Integer|nil }` when the year exists, then `redirect_back(fallback_location: root_path)`.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/term_contexts_controller_test.rb`. It asserts on `session`
directly (readable after a request in an integration test), so this task is
self-contained — it does not depend on the pre-fill wiring built in Tasks 3–4:

```ruby
require "test_helper"

class TermContextsControllerTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { username: users(:viewer).username, password: "password123" } }

  test "update stores a valid year and semester and redirects back" do
    patch term_context_path, params: { year_be: 2567, semester: 1 },
          headers: { "HTTP_REFERER" => reports_path }
    assert_redirected_to reports_path
    assert_equal({ "year_be" => 2567, "semester" => 1 }, session[:term_context])
  end

  test "update with a blank semester stores whole-year (nil semester)" do
    patch term_context_path, params: { year_be: 2567, semester: "" }
    assert_equal 2567, session[:term_context]["year_be"]
    assert_nil session[:term_context]["semester"]
  end

  test "update ignores a year that is not in the data" do
    patch term_context_path, params: { year_be: 1999, semester: 1 }
    assert_nil session[:term_context]
  end

  test "update falls back to root when there is no referer" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    assert_redirected_to root_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/term_contexts_controller_test.rb`
Expected: FAIL — no route `term_context_path` / uninitialized `TermContextsController`.

- [ ] **Step 3: Add the helper**

In `app/controllers/application_controller.rb`, add inside the class body (near the other helper methods). Add the method and expose it:

```ruby
  def current_term_context
    @current_term_context ||= TermContext.from_session(session)
  end
  helper_method :current_term_context
```

- [ ] **Step 4: Add the route**

In `config/routes.rb`, add (place it near the other top-level resources, e.g. just after `get "data_sources", ...`):

```ruby
  resource :term_context, only: :update
```

- [ ] **Step 5: Write the controller**

Create `app/controllers/term_contexts_controller.rb`:

```ruby
# Writes the user's working term into the session. The term is a pure default
# for report forms (see TermContext), so this stores a value and nothing more —
# it never runs a report or redirects anywhere but back where the user was.
class TermContextsController < ApplicationController
  def update
    year = params[:year_be].presence
    if year && Semester.exists?(year_be: year)
      session[:term_context] = { "year_be" => year.to_i, "semester" => params[:semester].presence&.to_i }
    end
    redirect_back(fallback_location: root_path)
  end
end
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bin/rails test test/controllers/term_contexts_controller_test.rb`
Expected: PASS — 4 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
hg add app/controllers/term_contexts_controller.rb test/controllers/term_contexts_controller_test.rb
hg commit app/controllers/application_controller.rb app/controllers/term_contexts_controller.rb config/routes.rb test/controllers/term_contexts_controller_test.rb -m "Nothing could set or read the working term across a request

TermContext can resolve a term from the session, but no code puts one there or
hands a shared instance to controllers and views. This adds both ends: a place
to read it and a place to write it.

- current_term_context on ApplicationController, memoized and exposed as a
  helper_method so controllers, helpers and views all read one instance
- TermContextsController#update stores the year+semester pair when the year is
  real, ignores an unknown year, and redirects back — it only ever stores a
  default, never runs anything

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Read-path 1 — the report DSL opt-in

**Files:**
- Modify: `app/services/reports/base.rb`
- Modify: `app/helpers/reports_helper.rb`
- Modify: `app/views/reports/_form.html.haml`
- Modify: `app/services/reports/semester_grade_distribution.rb`, `app/services/reports/failing_students.rb`, `app/services/reports/staff_courses_by_year.rb`
- Test: `test/services/reports/base_test.rb`, and additions to `test/controllers/reports_controller_test.rb`

**Interfaces:**
- Consumes: `current_term_context` (Task 2).
- Produces: `param name, type, context: :year | :semester | :semester_record` records `context:` in `params_spec`. `ReportsHelper#context_default_for(param) → value | nil` returns the projected value for an opted-in param, else nil. The report form pre-fills each field with `params[p[:name]].presence || context_default_for(p)`.

- [ ] **Step 1: Write the failing unit test**

Create `test/services/reports/base_test.rb`:

```ruby
require "test_helper"

class ReportsBaseTest < ActiveSupport::TestCase
  test "param records an explicit context opt-in" do
    year = Reports::SemesterGradeDistribution.params_spec.find { |p| p[:name] == :year }
    assert_equal :year, year[:context]
  end

  test "a param with no context opt-in carries nil" do
    prog = Reports::SemesterGradeDistribution.params_spec.find { |p| p[:name] == :program_group }
    assert_nil prog[:context]
  end

  test "admission_year params never opt in" do
    [Reports::CohortGpa, Reports::GroupCreditShortfall, Reports::ThesisCredits].each do |klass|
      adm = klass.params_spec.find { |p| p[:name] == :admission_year }
      assert_nil adm[:context], "#{klass}: admission_year must never draw from the sticky term"
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/reports/base_test.rb`
Expected: FAIL — `context` key absent (`nil` == `:year` fails on the first test).

- [ ] **Step 3: Add `context:` to the DSL**

In `app/services/reports/base.rb`, replace the `param` method:

```ruby
    def self.param(name, type, required: false, label: nil, context: nil)
      params_spec << { name: name, type: type, required: required, label: label, context: context }
      define_method(name) { @params[name.to_s] }
    end
```

- [ ] **Step 4: Opt in the three viewing-term reports**

In `app/services/reports/semester_grade_distribution.rb`, change the `year` and `term` params:

```ruby
    param    :year,          :academic_year, required: true, label: "Year (B.E.)", context: :year
    param    :term,          :term,          required: true, context: :semester
```

In `app/services/reports/failing_students.rb`:

```ruby
    param    :year,      :academic_year, required: true, label: "Year (B.E.)", context: :year
    param    :term,      :term,          context: :semester
```

In `app/services/reports/staff_courses_by_year.rb`:

```ruby
    param    :year,  :teaching_year, required: true, label: "Year (B.E.)", context: :year
```

Do **not** touch `admission_year` in `cohort_gpa.rb`, `group_credit_shortfall.rb`, or `thesis_credits.rb`.

- [ ] **Step 5: Run the unit test to verify it passes**

Run: `bin/rails test test/services/reports/base_test.rb`
Expected: PASS — 3 runs, 0 failures.

- [ ] **Step 6: Write the helper**

In `app/helpers/reports_helper.rb`, add:

```ruby
  # The default value a context-opted param should pre-fill with, or nil when the
  # param does not opt into the sticky term. Keyed by the param's context: axis.
  def context_default_for(param)
    return nil unless param[:context]
    ctx = current_term_context
    case param[:context]
    when :year            then ctx.academic_year_be
    when :semester        then ctx.semester_number
    when :semester_record then ctx.semester_record&.id
    end
  end
```

- [ ] **Step 7: Pre-fill the form**

In `app/views/reports/_form.html.haml`, compute the value once per param and use it in every branch. Replace the loop body so it reads:

```haml
  - @report.params_spec.each do |p|
    - val = params[p[:name]].presence || context_default_for(p)
    .col-md-3
      = label_tag p[:name], (p[:label] || p[:name].to_s.humanize), class: "form-label small text-muted"
      - case p[:type]
      - when :term
        = select_tag p[:name], options_for_select([["First", 1], ["Second", 2], ["Summer", 3]], val), include_blank: true, class: "form-select"
      - when :semester_record
        = select_tag p[:name], options_for_select(Semester.ordered.map { |s| [s.display_name, s.id] }, val), include_blank: true, class: "form-select"
      - when :program_group
        = select_tag p[:name], options_for_select(ProgramGroup.order(:code).map { |g| [g.short_label, g.code] }, val), include_blank: true, class: "form-select"
      - when :staff
        = select_tag p[:name], options_for_select(Staff.where.not(initials: [nil, ""]).sort_by(&:display_name_th).map { |s| ["#{s.display_name_th} (#{s.initials})", s.initials] }, val), include_blank: true, class: "form-select", data: { controller: "select2" }
      - when :teaching_year
        = select_tag p[:name], options_for_select(Semester.order(year_be: :desc).distinct.pluck(:year_be), val || Semester.maximum(:year_be)), class: "form-select"
      - when :boolean
        .form-check.mb-1
          = check_box_tag p[:name], "1", params[p[:name]] == "1", class: "form-check-input"
      - when :academic_year, :integer
        = number_field_tag p[:name], val, class: "form-control"
      - else
        = text_field_tag p[:name], val, class: "form-control"
```

(Only `:boolean` keeps `params[p[:name]]` — a checkbox has no context axis. The `:staff` comment block from the original file may be preserved; it is omitted here only for brevity.)

- [ ] **Step 8: Write the integration tests**

Add to `test/controllers/reports_controller_test.rb` (the `login` helper already exists there):

```ruby
  test "a viewing-year field pre-fills from the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("semester_grade_distribution")
    assert_select "input#year[value=?]", "2567"
    assert_select "select#term option[selected][value=?]", "1"
  end

  test "an explicit param overrides the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("semester_grade_distribution"), params: { year: 2568 }
    assert_select "input#year[value=?]", "2568"
  end

  test "a cohort report's admission_year is never filled from the sticky term" do
    login users(:viewer)
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get report_path("cohort_gpa")
    # admission_year must NOT be pre-filled with the context year
    assert_select "input#admission_year[value=?]", "2567", count: 0
  end
```

- [ ] **Step 9: Run the integration tests**

Run: `bin/rails test test/controllers/reports_controller_test.rb`
Expected: PASS — all existing tests plus the 3 new ones, 0 failures.

Also re-run Task 2's now-satisfied pre-fill assertions:

Run: `bin/rails test test/controllers/term_contexts_controller_test.rb`
Expected: PASS — 4 runs, 0 failures.

- [ ] **Step 10: Commit**

```bash
hg add test/services/reports/base_test.rb
hg commit app/services/reports/base.rb app/helpers/reports_helper.rb app/views/reports/_form.html.haml app/services/reports/semester_grade_distribution.rb app/services/reports/failing_students.rb app/services/reports/staff_courses_by_year.rb test/services/reports/base_test.rb test/controllers/reports_controller_test.rb -m "Hub report forms could not draw their term from the sticky context

The registry reports render from a param DSL, so the term default has to enter
through that DSL. It cannot key off the param TYPE: :academic_year means the
viewing year in some reports and the admission cohort in others, and feeding the
cohort reports the sticky year would silently show the wrong class of students.

- param gains an explicit context: opt-in (:year / :semester / :semester_record)
- context_default_for projects the sticky term onto an opted-in field, nil otherwise
- the form pre-fills each field from it; an explicit param still wins
- only the three viewing-term fields opt in; admission_year stays untouched, with
  a test proving a cohort report is never filled from the context

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Read-path 2 — the schedule pages

**Files:**
- Modify: `app/views/schedules/room.html.haml`, `staff.html.haml`, `student.html.haml`, `curriculum.html.haml`, `conflicts.html.haml`
- Modify: `app/controllers/schedules_controller.rb` (teaching-matrix action)
- Test: additions to `test/controllers/schedules_controller_test.rb`

**Interfaces:**
- Consumes: `current_term_context` (Task 2).
- Produces: the five calendar pages preselect the context semester in their semester dropdown when `params[:semester_id]` is blank; the teaching-matrix action defaults `@year`/`@semester_number` from the context. Explicit params always win.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/schedules_controller_test.rb` (its `setup` already logs in as `users(:viewer)`):

```ruby
  test "room preselects the context semester when none is given" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get schedules_room_path
    assert_select "select#semester_id option[selected][value=?]", semesters(:sem_2567_1).id.to_s
  end

  test "room honors an explicit semester over the context" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get schedules_room_path, params: { semester_id: semesters(:sem_2568_2).id }
    assert_select "select#semester_id option[selected][value=?]", semesters(:sem_2568_2).id.to_s
  end

  test "teaching matrix defaults its year to the context year" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get schedules_teaching_matrix_path
    assert_select "input#year[value=?]", "2567"
  end

  test "teaching matrix honors an explicit year over the context" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    get schedules_teaching_matrix_path, params: { year: 2568 }
    assert_select "input#year[value=?]", "2568"
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/schedules_controller_test.rb -n "/context/"`
Expected: FAIL — the semester/year defaults still come from `params` only.

- [ ] **Step 3: Preselect the context semester in the five calendar views**

In each of `app/views/schedules/room.html.haml`, `staff.html.haml`, `student.html.haml`, `curriculum.html.haml`, `conflicts.html.haml`, find the semester `select_tag` (the one bound to `:semester_id`) and change its selected-value argument from `params[:semester_id]` to:

```
params[:semester_id].presence || current_term_context.semester_record&.id
```

For example in `room.html.haml` the line becomes:

```haml
        = select_tag :semester_id, options_for_select(@semesters.map { |s| ["#{s.display_name} — #{Semester::SEMESTER_LABELS[s.semester_number]}", s.id] }, params[:semester_id].presence || current_term_context.semester_record&.id), include_blank: "Select semester", class: "form-select form-select-sm", data: { controller: "select2" }
```

Apply the identical `params[:semester_id].presence || current_term_context.semester_record&.id` substitution in the other four views. Do not change the controller run logic — these pages still require an explicit submitted `semester_id` (and their other entity) to render results; this only sets the dropdown's default.

- [ ] **Step 4: Default the teaching-matrix year/semester from context**

In `app/controllers/schedules_controller.rb`, in the `teaching_matrix` action, the current defaults are:

```ruby
    @year = (params[:year].presence || default_year).to_i
    @semester_number = params[:semester_number].presence&.to_i
```

Change them to draw from the context first (explicit param still wins, `default_year` remains the final fallback):

```ruby
    @year = (params[:year].presence || current_term_context.academic_year_be || default_year).to_i
    @semester_number = (params[:semester_number].presence || current_term_context.semester_number)&.to_i
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/schedules_controller_test.rb`
Expected: PASS — all existing tests plus the 4 new ones, 0 failures. (The existing `"teaching matrix defaults to the latest year with teachings"` test passes `year`-free requests; with fixtures the context default year is 2568, which is what that test already expects, so it stays green.)

- [ ] **Step 6: Commit**

```bash
hg commit app/views/schedules/room.html.haml app/views/schedules/staff.html.haml app/views/schedules/student.html.haml app/views/schedules/curriculum.html.haml app/views/schedules/conflicts.html.haml app/controllers/schedules_controller.rb test/controllers/schedules_controller_test.rb -m "The schedule pages ignored the sticky term the rest of the app now honours

The schedule calendars are hand-rolled pages that read params directly, so they
did not benefit from the report-DSL opt-in. Each now falls back to the working
term when no term is given, matching the hub reports.

- The five calendar pages preselect the context semester when semester_id is blank
- The teaching matrix defaults its year and semester from the context
- An explicit param still wins in every case, so existing deep links are unchanged
- workload is left alone deliberately: it is a multi-year range, not a single term

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The context bar

**Files:**
- Create: `app/views/shared/_term_context_bar.html.haml`
- Create: `app/javascript/controllers/term_context_controller.js`
- Modify: `app/views/reports/index.html.haml`, `app/views/reports/show.html.haml`
- Modify: `app/views/schedules/room.html.haml`, `staff.html.haml`, `student.html.haml`, `curriculum.html.haml`, `conflicts.html.haml`, `teaching_matrix.html.haml`
- Test: `test/integration/term_context_bar_test.rb`

**Interfaces:**
- Consumes: `current_term_context` (Task 2), `term_context_path` (Task 2), `params_spec[...][:context]` (Task 3).
- Produces: a `.term-context-bar` element rendered on the reports hub, on consuming registry report show pages, and on the six schedule calendar pages; absent from cohort reports and from `workload`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/term_context_bar_test.rb`:

```ruby
require "test_helper"

class TermContextBarTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { username: users(:viewer).username, password: "password123" } }

  test "the bar appears on the reports hub" do
    get reports_path
    assert_select ".term-context-bar"
  end

  test "the bar appears on a report that consumes the term" do
    get report_path("semester_grade_distribution")
    assert_select ".term-context-bar"
  end

  test "the bar is absent from a cohort report that ignores the term" do
    get report_path("cohort_gpa")
    assert_select ".term-context-bar", count: 0
  end

  test "the bar appears on the schedule calendars" do
    get schedules_room_path
    assert_select ".term-context-bar"
    get schedules_teaching_matrix_path
    assert_select ".term-context-bar"
  end

  test "the bar is absent from the workload range report" do
    get schedules_workload_path
    assert_select ".term-context-bar", count: 0
  end

  test "the bar shows the resolved default term" do
    get reports_path
    # default over fixtures is 2568 / semester 2
    assert_select ".term-context-bar select#year_be option[selected][value=?]", "2568"
    assert_select ".term-context-bar select#semester option[selected][value=?]", "2"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/term_context_bar_test.rb`
Expected: FAIL — no `.term-context-bar` anywhere.

- [ ] **Step 3: Write the Stimulus controller**

Create `app/javascript/controllers/term_context_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Submits the term-context form as soon as either dropdown changes, so setting a
// working term takes effect without a separate button. The controller is on the
// <form> element; requestSubmit() fires the PATCH and the controller redirects back.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
```

- [ ] **Step 4: Write the partial**

Create `app/views/shared/_term_context_bar.html.haml`:

```haml
-# Sets the user's working term (see TermContext). Renders on report pages only.
-# Copy is neutral ("Working in") — it shows the current context, it does not claim
-# to filter the page it sits on.
.term-context-bar.d-flex.align-items-center.gap-2.mb-3
  - if Semester.exists?
    - ctx = current_term_context
    %span.small.text-muted.text-uppercase.fw-semibold Working in
    = form_with url: term_context_path, method: :patch, class: "d-flex gap-2 mb-0", data: { controller: "term-context" } do
      = select_tag :year_be,
          options_for_select(Semester.distinct.order(year_be: :desc).pluck(:year_be), ctx.academic_year_be),
          class: "form-select form-select-sm w-auto", data: { action: "term-context#submit" }
      = select_tag :semester,
          options_for_select([["Whole year", ""], ["1", 1], ["2", 2], ["Summer", 3]], ctx.semester_number),
          class: "form-select form-select-sm w-auto", data: { action: "term-context#submit" }
  - else
    %span.small.text-muted No terms yet
```

- [ ] **Step 5: Render it on the hub and consuming report pages**

In `app/views/reports/index.html.haml`, add the bar just inside `.card-body.p-3`, before the title row (`.d-flex.justify-content-between...`):

```haml
    = render "shared/term_context_bar"
```

In `app/views/reports/show.html.haml`, insert between the title row (ends at the `= link_to "Back"...` line) and `.card.mb-3`:

```haml
- if @report.params_spec.any? { |p| p[:context] }
  = render "shared/term_context_bar"
```

- [ ] **Step 6: Render it on the six schedule calendars**

In each of `room.html.haml`, `staff.html.haml`, `student.html.haml`, `curriculum.html.haml`, `conflicts.html.haml`, `teaching_matrix.html.haml`, insert immediately after the title `.d-flex.justify-content-between.align-items-center.mb-3` block (the one containing the `%h1` and the "Back" link) and before `.card.mb-3`:

```haml
= render "shared/term_context_bar"
```

Do **not** add it to `workload.html.haml`.

- [ ] **Step 7: Run the test to verify it passes**

Run: `bin/rails test test/integration/term_context_bar_test.rb`
Expected: PASS — 7 runs, 0 failures.

- [ ] **Step 8: Commit**

```bash
hg add app/views/shared/_term_context_bar.html.haml app/javascript/controllers/term_context_controller.js test/integration/term_context_bar_test.rb
hg commit app/views/shared/_term_context_bar.html.haml app/javascript/controllers/term_context_controller.js app/views/reports/index.html.haml app/views/reports/show.html.haml app/views/schedules/room.html.haml app/views/schedules/staff.html.haml app/views/schedules/student.html.haml app/views/schedules/curriculum.html.haml app/views/schedules/conflicts.html.haml app/views/schedules/teaching_matrix.html.haml test/integration/term_context_bar_test.rb -m "The working term could be read but never set from the UI

Tasks 1-4 made every relevant report read a sticky term, but a user had no way
to choose one. This adds the control: a small two-dropdown bar that writes the
session on change.

- A shared partial rendered on the reports hub, the schedule calendars, and any
  registry report that actually consumes the term
- Kept off the cohort reports (data-driven: only reports with a context-opted
  param show it) and off workload, so the bar never implies it filters a page
  that ignores it
- Submit-on-change via a Stimulus controller; neutral 'Working in' copy

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: End-to-end system test and final verification

**Files:**
- Test: `test/system/term_context_test.rb`

**Interfaces:**
- Consumes: everything from Tasks 1–5.

- [ ] **Step 1: Write the system test**

Create `test/system/term_context_test.rb`:

```ruby
require "application_system_test_case"

class TermContextTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  # Each test changes only the YEAR dropdown — one submit-on-change per interaction —
  # and waits for the reload (the bar showing the new year selected) before navigating,
  # so there is no race between the auto-submit and the next step.

  test "setting the term pre-fills a consuming report" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"
    visit report_path("failing_students")
    assert_selector "input#year[value='2567']"
  end

  test "changing the term on a report does not change the sticky setting" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"

    # Override the year on one report's own form (do not submit it anywhere sticky).
    visit report_path("failing_students")
    fill_in "year", with: "2568"

    # A different consuming report still reflects the sticky 2567, not the override.
    visit report_path("semester_grade_distribution")
    assert_selector "input#year[value='2567']"
  end

  test "a range report ignores the sticky term" do
    visit reports_path
    within(".term-context-bar") { select "2567", from: "year_be" }
    assert_selector ".term-context-bar select#year_be option[selected][value='2567']"
    visit schedules_workload_path
    assert_no_selector ".term-context-bar"
  end
end
```

- [ ] **Step 2: Run the system test**

Run: `bin/rails test test/system/term_context_test.rb`
Expected: PASS — 3 runs, 0 failures, 0 errors.

If a failure is a `geckodriver`/`Firefox` driver error rather than an assertion failure, note it and report DONE_WITH_CONCERNS — the environment has a known geckodriver 0.36.0 / Firefox 150.0.1 mismatch that fails JS-widget interactions. The selects in the bar are plain `<select>` elements (no Select2), so they should drive cleanly; a driver failure here is worth flagging.

- [ ] **Step 3: Commit**

```bash
hg add test/system/term_context_test.rb
hg commit test/system/term_context_test.rb -m "No end-to-end proof that the sticky term actually flows through the UI

The unit and integration tests cover each piece; this proves the whole path in a
browser: set the term in the bar, and a report form opened afterwards is
pre-filled — while overriding a term on one report leaves the sticky setting, and
other reports, untouched.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Full-suite verification (controller runs this, not a task subagent)**

Run: `bin/rails test`
Expected: green (aside from the pre-existing, environment-related system failures documented for this repo).

Run: `bin/rails test test/system/term_context_test.rb`
Expected: PASS.

---

## Post-implementation

Per `CLAUDE.md`, `docs/backlog.md` holds triggered items when a report or entity show page changes. This plan changes how report *forms default*, not what any report computes and not any entity show page — so open `docs/backlog.md` and confirm nothing is triggered before calling the work done.

Confirm the spec's contract holds end to end:

- [ ] Setting a term in the bar pre-fills the nine consuming reports (5 schedule calendars, teaching matrix, semester grade distribution, failing students, staff-courses-by-year).
- [ ] The three cohort reports and the two range reports (workload, class distribution) are never filled from the context — proven by the cohort test in Task 3 and the bar-absence tests in Task 5.
- [ ] An explicit param or deep link always overrides the context.
- [ ] No report's `#run` was modified — the feature changes defaults only.
