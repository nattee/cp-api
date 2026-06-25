# Web Report Layer + Per-Program FAQ Menu — Design Spec

- **Date:** 2026-06-25
- **Status:** Approved (design); pending implementation plan
- **Scope:** v1 = shared query/report layer + web FAQ menu (transcript-side reports only)
- **Lifecycle:** Short-lived scaffolding. Delete this spec (and its plan) once the feature ships
  and the durable knowledge has migrated into `CLAUDE.md` / `docs/`.

## North star (why this exists)

The department wants a system that helps staff **check each student's status — their progress
through the program**: where a student stands against their curriculum's requirements (credits per
category, required courses, thesis credits, GPA, etc.).

A LINE LLM chatbot (tool-calling over `student_lookup` / `course_lookup` / `staff_lookup` /
`search`) already exists. Staff asked for the **same answers on the web**, surfaced as a menu of
frequently-asked questions that **differ per program**. Real examples gathered:

1. Who teaches this subject? (every program)
2. Which students failed this subject?
3. Who hasn't enrolled in enough credits for this *course group*?
4. (Master) how many thesis credits has each student enrolled?
5. Which courses did *X* teach last year?

These are all **deterministic database queries** asked by **staff/advisors** about cohorts of
students — not open-ended advice. The LLM is unnecessary to *compute* them.

## Feasibility finding (can current data model this?)

A degree audit has two halves:

- **Transcript side (what the student has done) — well-modeled today.** `grades`
  (`student_id`, `course_id`, `grade`, `grade_weight`, `credits_grant`, `year`, `semester`, unique
  per term) is effectively a transcript. `courses` carries `credits`, `course_group`, `is_gened`,
  `is_thesis`, `program_id`, `revision_year`. `students` ties to `program_id` / `admission_year_be`.
- **Requirements side (what the program requires) — NOT modeled.** No requirements table; nothing
  states "CP rev 2566 needs N credits from group X / these required courses / total / thesis." The
  `course_group` column is a free-text string that *groups* the catalog but carries no thresholds.

**Decision:** v1 builds only what the transcript side supports. The requirements side
(`CurriculumRequirement` + a full degree-audit view) is a **follow-on spec**.

**Unverified data-quality items (could not run live DB in this environment — gems not installed).
De-risk before the follow-on spec:**
1. Is `course_group` populated and **consistent** across courses and revisions?
2. Are `grades` **complete** per student (all terms; transfer/exempted credits — `old_program` hints
   some transfer-in)?
3. Do the **official requirement numbers** exist in a documentable form per program/revision?

## Decomposition (full north star → sub-projects)

1. **This spec — shared query + report layer & web FAQ menu.** Transcript-side reports. Feasible
   today. Also the web home for the LINE-shared query layer.
2. **`CurriculumRequirement` model + seeds.** Encode per-program/revision requirements. Blocked on
   the data-availability question above, not on engineering.
3. **Degree-audit / progress view.** Per-student progress = transcript × requirements. Built on 1+2.

## Key decisions (from brainstorming)

- **Hybrid (Approach C for UX):** deterministic reports for the known questions + the existing
  free-form LLM chat (`/chat`) for the long tail — both on **one shared query layer**.
- **Shared layer = query objects + thin presenters (Approach A):** query objects return **pure Ruby
  data**; web renders HAML tables, LINE serializes JSON for the LLM. This resolves the old
  `docs/llm-data-query.md` objection ("don't share query objects, shapes differ") by sharing the
  *query* and splitting the *presentation*.
- **Menu = reports dashboard (Approach C for menu):** grouped into sections, with a program selector
  at the top that filters/scopes which reports show.
- **Audience = staff/advisor.** `before_action :require_admin`, matching the existing admin-only
  `/chat`. (Revisit if editors/viewers need access.)
- **Question #3 threshold = parameterized for v1.** Staff types the required-credit threshold into
  the form. No new model now; graduates to `CurriculumRequirement` in the follow-on. The shared
  query object stays identical — only where the threshold *comes from* changes.
- **LINE gets the reports via ONE new tool** (`report_query`, enum-dispatched), not five. See §5.

---

## §1 — Shared query layer (directory + contract)

Matches the existing `app/services/{importers,exporters,scrapers,line}/` convention.

```
app/services/reports/
  base.rb              # Reports::Base — DSL + shared helpers
  result.rb            # Reports::Result — structured return value
  registry.rb          # Reports::Registry — enumerates reports for the menu
  course_teachers.rb
  failing_students.rb
  group_credit_shortfall.rb
  thesis_credits.rb
  staff_courses_by_year.rb
```

**`Reports::Base`** defines a small class-level DSL (plain class methods, in the spirit of Rails'
`has_many` / `validates` / `before_action`) plus shared instance helpers:

```ruby
class Reports::Base
  # ---- DSL: class methods used to declare a report ----
  def self.title(text = nil)   = text ? @title = text   : @title
  def self.section(sym = nil)  = sym  ? @section = sym   : @section
  def self.programs(val = nil) = val  ? @programs = val  : (@programs || :all)

  def self.params_spec = (@params_spec ||= [])

  # each `param` feeds BOTH the web form (§3) and an accessor used inside #run
  def self.param(name, type, required: false)
    params_spec << { name:, type:, required: }
    define_method(name) { @params[name.to_s] }
  end

  # ---- helpers ----
  def self.applicable_to?(group)
    programs == :all || Array(programs).include?(group.code.to_sym)
  end

  def initialize(params = {}) = @params = params.stringify_keys

  # resolve a :semester param → Semester record (latest if blank)
  def semester_scope
    semester.present? ? Semester.find_by(year_be:, semester_number:) : Semester.ordered.first
  end

  # structured return; infers columns from row keys unless declared
  def result(rows:, summary: nil, columns: nil)
    columns ||= rows.first&.keys&.map { |k| { key: k, label: k.to_s.humanize } } || []
    Reports::Result.new(columns:, rows:, summary:)
  end
end
```

**A report subclass** is ~6 declarative lines + one `run`:

```ruby
class Reports::FailingStudents < Reports::Base
  title    "Which students failed this subject"
  section  :courses
  programs :all
  param    :course_no, :course,        required: true
  param    :year,      :academic_year, required: true
  param    :semester,  :semester

  def run
    scope = Grade.graded.joins(:course, :student)
                 .where(courses: { course_no: course_no }, grade: "F", year: year)
    scope = scope.where(semester: semester) if semester.present?   # optional :semester param
    rows  = scope.map { |g| { student_id: g.student.student_id,
                              name: g.student.display_name,
                              term: "#{g.year}/#{g.semester}", grade: g.grade } }
    result(rows:, summary: "#{rows.size} student(s) failed #{course_no}")
  end
end
```

(The base `semester_scope` helper above is for reports keyed by a whole `Semester` record —
e.g. `CourseTeachers`, `StaffCoursesByYear`; `FailingStudents` instead filters by the raw
`year`/`semester` params, since grades are stored per term.)

**`Reports::Result`** — the single value both surfaces consume:

```ruby
Reports::Result.new(
  columns: [ { key: :student_id, label: "Student ID" }, { key: :name, label: "Name" }, … ],
  rows:    [ { student_id: "65…", name: "…", grade: "F", term: "2568/1" }, … ],
  summary: "12 students failed 2110327"
)
```

> **Invariant:** `run` returns pure data — never HTML, never prose. That is what lets one query
> serve both the web table and the LINE JSON.

## §2 — Registry + per-program menu

- `Reports::Registry.all` — enumerates `Reports::Base` subclasses.
- `.for_program(group)` — filters by each report's `programs` declaration (so `thesis_credits`
  hides for bachelor programs).
- `.grouped` — buckets by `section`.
- `SECTIONS` constant labels groups (e.g. Courses / Students / Curriculum / Thesis).

`/reports` dashboard renders cards from the registry; a program selector (select2) at the top
filters which cards show. **Adding a report = adding one file; no menu edits.**

## §3 — `ReportsController` + flow

- `index` → dashboard (grouped cards + program selector).
- `show` → param form **generated from the report's `param` declarations** via a generic `_form`
  partial keyed by param type (`:course`→select2, `:semester`→dropdown, `:academic_year`/`:integer`
  →inputs). Same data-driven spirit as the importer-mapping UI.
- submit → re-renders `show` with the `Result` as a DataTable + summary + **Export CSV** (reuse the
  `Exporters` pattern) + an **"Ask a follow-up"** link into `/chat`.
- `before_action :require_admin` (staff/advisor audience; matches `/chat`).

Routes: `resources :reports, only: [:index, :show]`, with the form submit re-hitting `show` with
query params (or a dedicated `run` member — decide in the plan).

## §4 — The five reports (feasibility-checked)

| Report | Section / programs | Params | Query → columns |
|---|---|---|---|
| `CourseTeachers` | courses / all | course_no, [semester] | CourseOffering→Section→Teaching→Staff → course, section, instructor |
| `FailingStudents` | courses / all | course_no, year, [semester] | `Grade.graded` grade=`F` → student_id, name, term, grade |
| `GroupCreditShortfall` | curriculum / all | course_group, **required_credits**, [admission_year] | sum `credits_grant` per student in group (passed) < threshold → student_id, name, earned, required, missing |
| `ThesisCredits` | thesis / **master only** | [admission_year or student] | `Grade`⋈`courses.is_thesis` sum per student → student_id, name, thesis_credits |
| `StaffCoursesByYear` | courses / all | staff, year | Teaching→Section→CourseOffering→Course by year → course_no, name, section |

Notes:
- `FailingStudents` uses grade `F` for v1. Whether to include `U` (unsatisfactory) is an open
  question — default `F` only; revisit if staff want S/U courses counted.
- `GroupCreditShortfall` counts only *passing* grades toward earned credits (`Grade.graded`,
  excluding `F`/`W`/etc. by `credits_grant`). The threshold is a typed param (v1).
- `ThesisCredits` relies on `courses.is_thesis`; only offered for master program groups (CM/CS/SE).

## §5 — LINE adapter, errors, tests

**LINE adapter — one tool, enum-dispatched.** Add a single `report_query` tool with a `report_key`
enum + the shared params; it dispatches to the same `Reports::X.run` and `.to_json`s
`rows` + `summary`.

- **Why one tool, not five:** the bot runs self-hosted **Qwen 2.5 Coder 32B / GLM-4 / Kimi** via
  vLLM and is **already at 6 registered tools** (`student_lookup`, `staff_lookup`, `course_lookup`,
  `course_offering_lookup`, `search`, `echo`). Per `docs/llm-data-query.md`, 32B-class open models
  degrade around **8–10 tools** — they confuse *similar* tools and mis-extract Thai params. Five new
  report tools (→ 11) would also heavily overlap existing lookups. One `report_query` tool keeps the
  count at **6 → 7**, turns selection into a binary "is this a report?" + a constrained enum pick,
  and keeps tool-definition context ~constant as reports are added. This is the enum-dispatch pattern
  the old doc proposed — now justified because the reports share one query layer.
- **Guardrail (bake into the codebase conventions):** keep top-level tools ≤ ~7; push variety into
  enums, never new tools; crisp non-overlapping tool descriptions; E2E-test tool selection across
  all three models.
- **Sequencing:** web-first. The LINE tool is a thin add and may be deferred within v1 if time runs
  short.

**Error handling / edges:**
- Missing required param → form validation error (re-render `show`).
- No course/staff match → friendly "no match" result (not an exception).
- Empty rows → a "no students matched" *summary*, rendered as a normal (empty) result, not an error.
- `semester` blank → defaults to latest via `Semester.ordered.first`.
- Authorization via `require_admin`.

**Testing (per user preference — written AFTER implementation; ask before writing, per `CLAUDE.md`):**
- Unit test per report query (fixtures: students, grades, courses, teachings, sections).
- One system test: dashboard renders + run one report end-to-end (happy path) + one empty-result case.
- The plan sequences tests last.

---

## File manifest

**New:**
- `app/services/reports/base.rb`, `result.rb`, `registry.rb`
- `app/services/reports/{course_teachers,failing_students,group_credit_shortfall,thesis_credits,staff_courses_by_year}.rb`
- `app/controllers/reports_controller.rb`
- `app/views/reports/index.html.haml`, `show.html.haml`, `_form.html.haml`, `_result_table.html.haml`
- `app/services/line/tools/report_query_tool.rb` (LINE adapter; may defer within v1)
- Tests under `test/services/reports/` and `test/system/reports_test.rb` (last)

**Modified:**
- `config/routes.rb` — `resources :reports, only: [:index, :show]`
- `config/initializers/line_tools.rb` — register `report_query` (if LINE adapter included)
- `app/helpers/application_helper.rb` — `RESOURCE_ICONS["reports"]` + sidebar nav entry
- `config/llm.yml` system prompt — one line mentioning the report capability (if LINE adapter included)

## Out of scope / future (follow-on specs)

- `CurriculumRequirement` model + seeds (replaces the typed threshold in `GroupCreditShortfall`).
- Full per-student degree-audit / progress view.
- Migrating the existing LINE lookup tools onto the shared `Reports::` query layer.
- Editor/viewer access (currently admin-only).

## Open questions

1. `FailingStudents`: include `U` alongside `F`? (default: `F` only)
2. `ReportsController`: form submit → re-render `show` with query params, or a dedicated `run` member?
3. Include the LINE `report_query` tool in v1, or ship web-only first?
