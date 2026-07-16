# Data Coverage Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Reports::DataCoverage` admin report — a per-term matrix of grades / schedule / new-student counts with era-aware red/yellow cell flagging — so a semester whose import or scrape was missed is visually obvious.

**Architecture:** One new report class in the existing `Reports::` framework (registry + auto form + shared result table + free CSV), plus two small generic framework extensions: a `:boolean` param type (checkbox) in the form partial and a per-cell CSS-class hook (`class_key:` on column specs) in the result table partial. Spec: `docs/superpowers/specs/2026-07-16-data-coverage-report-design.md`.

**Tech Stack:** Rails 8.1, HAML, Minitest + fixtures, Dart Sass, Mercurial (NOT git).

## Global Constraints

- **Version control is Mercurial.** `hg add <file>` / `hg commit <files> -m "..."` — NEVER git commands. Always name explicit files in `hg commit` (the repo often has unrelated dirty changes).
- **Commit messages lead with WHY**, not what: first paragraph = problem/motivation, then the what.
- Templates are **HAML**, styles are SCSS compiled by `bin/rails dartsass:build` (run it after any `.scss` change).
- **Intranet-only** app: no external URLs/CDNs anywhere.
- Year fields in UI copy must name the era (B.E.) where ambiguous; the Term column values are B.E. (`2569/1`) — this is the house convention.
- Tests come **after** the feature (tasks 4), matching the maintainer's workflow — do not reorder into TDD.
- Working directory: `/home/dae/cp-api`. Test commands: `bin/rails test <file>`, `bin/rails test:system`.

---

### Task 1: Framework extensions (`:boolean` param, `class_key` cell classes, SCSS)

Small generic additions the report needs; independently reviewable as "the reports framework can now render checkboxes and flag cells".

**Files:**
- Modify: `app/views/reports/_form.html.haml` (add `when :boolean` branch)
- Modify: `app/views/reports/_result_table.html.haml` (apply `class_key`)
- Modify: `app/services/reports/base.rb` (comment only: document the new param type)
- Modify: `app/assets/stylesheets/application.scss` (two cell-flag classes)

**Interfaces:**
- Consumes: nothing new.
- Produces (Task 2 relies on):
  - `param :name, :boolean` renders a checkbox that submits `"1"` when checked (absent when unchecked).
  - A column spec `{ key: :grades, label: "Grades", class_key: :grades_class }` makes the table apply `row[:grades_class]` as the `<td>` CSS class. Rows without the key render a plain cell. CSV export is unaffected (`Exporters::ReportExporter` reads only `col[:key]` — already true, no change).
  - CSS classes `report-cell-missing` (red) and `report-cell-low` (yellow).

- [ ] **Step 1: Add the `:boolean` branch to the form partial**

In `app/views/reports/_form.html.haml`, the widget is chosen by `case p[:type]`. Add a `when :boolean` branch immediately before the `when :academic_year, :integer` branch:

```haml
      - when :boolean
        -# Checkbox params submit "1" when checked and are simply absent when not.
        -# The generic label_tag above targets this input's id, so clicking the
        -# label toggles the box.
        .form-check.mb-1
          = check_box_tag p[:name], "1", params[p[:name]] == "1", class: "form-check-input"
```

(Indentation: the `when` lines sit at the same depth as the existing `when :term`.)

- [ ] **Step 2: Document the new type in the Base DSL comment**

In `app/services/reports/base.rb`, the `param` docstring lists valid types:

```ruby
    # type ∈ :course, :staff, :course_group, :academic_year, :teaching_year, :integer, :term, :semester_record, :program_group
```

Change it to:

```ruby
    # type ∈ :course, :staff, :course_group, :academic_year, :teaching_year, :integer, :term, :semester_record, :program_group, :boolean
```

- [ ] **Step 3: Apply `class_key` in the result table partial**

In `app/views/reports/_result_table.html.haml`, the body cell line is currently:

```haml
              - @result.columns.each do |col|
                %td= row[col[:key]]
```

Change to:

```haml
              - @result.columns.each do |col|
                -# Optional per-cell flag: a column may declare class_key:; the row
                -# then carries that key with a CSS class ("report-cell-missing").
                -# CSV export ignores it (ReportExporter reads only col[:key]).
                %td{class: (row[col[:class_key]] if col[:class_key])}= row[col[:key]]
```

- [ ] **Step 4: Add the two cell-flag classes to `application.scss`**

Place directly after the "Enrollment source badges" / `.badge-course-group` block (search for `.badge-course-group`), before the "Data-source operating-mode badges" comment:

```scss
// Report cell flags — generic per-cell highlighting for Reports:: results
// (a column declares class_key:, the row carries one of these classes; see
// reports/_result_table). First user: Reports::DataCoverage (red = a term's
// dataset is missing, yellow = suspiciously low vs. same-semester median).
// Frosted tints like the badges above, but subtler: a whole <td> is a lot of
// area, so lower alpha than the badge 0.2 — and an inset box-shadow instead
// of a border, because td borders are managed by the table border rules
// (post-import $table-row-border-color) and a real border would fight them.
.report-cell-missing { background-color: rgba($danger, 0.14);  box-shadow: inset 0 0 0 1px rgba($danger, 0.35); }
.report-cell-low     { background-color: rgba($warning, 0.12); box-shadow: inset 0 0 0 1px rgba($warning, 0.30); }
```

- [ ] **Step 5: Rebuild CSS and verify**

Run: `bin/rails dartsass:build`
Expected: exits 0, no Sass errors.

Run: `grep -c "report-cell-missing" app/assets/builds/application.css`
Expected: `1` (or more) — the class made it into the build.

- [ ] **Step 6: Commit**

```bash
hg commit app/views/reports/_form.html.haml app/views/reports/_result_table.html.haml app/services/reports/base.rb app/assets/stylesheets/application.scss app/assets/builds/application.css -m "Reports framework: boolean params and per-cell flag classes

The upcoming data-coverage report needs a checkbox filter and red/yellow
cell highlighting, and the framework had neither: param types had no
boolean, and the shared result table rendered plain values only. Both
additions are generic so any report can use them; CSV export is
unaffected because the exporter reads only declared column keys.

- _form: when :boolean -> check_box_tag submitting \"1\"
- _result_table: optional column class_key applied as the td class
- SCSS: .report-cell-missing / .report-cell-low frosted tints"
```

(If `app/assets/builds/application.css` is not tracked by hg — check with `hg status app/assets/builds/` — omit it from the commit.)

---

### Task 2: `Reports::DataCoverage` + registry entry

**Files:**
- Create: `app/services/reports/data_coverage.rb`
- Modify: `app/services/reports/registry.rb` (new `admin:` section + one REPORTS line)

**Interfaces:**
- Consumes (from Task 1): `param :program_courses_only, :boolean`; column `class_key:`; CSS classes `report-cell-missing` / `report-cell-low`.
- Produces (Tasks 3–5 rely on): report key `"data_coverage"` (URL `/reports/data_coverage`), title `"Which terms are missing data"`, registry section `:admin` labeled `"Data"`. Row hashes carry keys `:term, :new_students, :grades, :ungraded, :offerings, :sections, :time_slots` plus optional `:<key>_class` flags. Params: `"program_courses_only" => "1"` restricts course-based counts to curriculum courses.

**Domain facts you need (do not re-derive):**
- `Grade#year_ce` is Gregorian; everything else is Buddhist Era (B.E. = C.E. + 543). Terms are keyed `[year_be, semester_number]`.
- `Semester(year_be, semester_number)` is the schedule parent: `CourseOffering belongs_to :semester, :course`; `Section belongs_to :course_offering`; `TimeSlot belongs_to :section`.
- `Student#admission_year_be` = cohort year. New students are only expected on semester-1 rows.
- `ProgramCourse(program_id, course_id)` marks a course as part of some curriculum.
- `Program#placeholder?` is the `"0000"` catch-all program — exempt from the curriculum diagnostic.

- [ ] **Step 1: Create the report class**

`app/services/reports/data_coverage.rb` — complete file:

```ruby
module Reports
  # "Which terms are missing data" — per-term coverage matrix (data presence,
  # NOT import-run audit: data_imports rows don't know which term a file
  # covered, and data also arrives via scraper and ChulaBooster sync).
  # One row per term (union of Semester records and grade terms), one column
  # per dataset, era-aware red/yellow flags so a missed term stands out.
  # Design: docs/superpowers/specs/2026-07-16-data-coverage-report-design.md
  class DataCoverage < Base
    title    "Which terms are missing data"
    section  :admin
    programs :all
    param    :program_courses_only, :boolean, label: "Program courses only"

    MISSING_CLASS = "report-cell-missing".freeze
    LOW_CLASS     = "report-cell-low".freeze
    LOW_RATIO     = 0.5          # yellow when below this fraction of the peer median
    BLANK         = "—".freeze   # predates the dataset / not applicable

    # Count columns that get era + red/yellow treatment. :ungraded is
    # deliberately absent — zero ungraded is GOOD, so it is informational
    # only (it just goes BLANK alongside :grades outside the grades era).
    FLAGGED_KEYS = %i[new_students grades offerings sections time_slots].freeze

    def run
      terms  = collect_terms
      counts = build_counts
      rows   = terms.map { |t| build_row(t, counts) }
      apply_flags!(rows, terms)
      result(columns: columns_spec, rows: rows, summary: summary_text(rows))
    end

    private

    def columns_spec
      [
        { key: :term,         label: "Term" },
        { key: :new_students, label: "New Students", class_key: :new_students_class },
        { key: :grades,       label: "Grades",       class_key: :grades_class },
        { key: :ungraded,     label: "Ungraded" },
        { key: :offerings,    label: "Offerings",    class_key: :offerings_class },
        { key: :sections,     label: "Sections",     class_key: :sections_class },
        { key: :time_slots,   label: "Time Slots",   class_key: :time_slots_class }
      ]
    end

    # Every term that has a Semester record or any grade, newest first,
    # as [year_be, semester_number] pairs. Summer terms appear naturally.
    def collect_terms
      semester_terms = Semester.pluck(:year_be, :semester_number)
      grade_terms = Grade.distinct.pluck(:year_ce, :semester)
                         .map { |year_ce, sem| [year_ce + 543, sem] }
      (semester_terms + grade_terms).uniq.sort.reverse
    end

    def program_courses_only?
      program_courses_only == "1"
    end

    # One grouped count per dataset, keyed [year_be, semester_number].
    def build_counts
      curriculum = ProgramCourse.select(:course_id)
      grades    = Grade.all
      offerings = CourseOffering.joins(:semester)
      sections  = Section.joins(course_offering: :semester)
      slots     = TimeSlot.joins(section: { course_offering: :semester })
      if program_courses_only?
        grades    = grades.where(course_id: curriculum)
        offerings = offerings.where(course_id: curriculum)
        sections  = sections.where(course_offerings: { course_id: curriculum })
        slots     = slots.where(course_offerings: { course_id: curriculum })
      end
      to_be = ->(h) { h.transform_keys { |(year_ce, sem)| [year_ce + 543, sem] } }
      sem_group = ["semesters.year_be", "semesters.semester_number"]
      {
        new_students: Student.group(:admission_year_be).count,
        grades:       to_be.(grades.group(:year_ce, :semester).count),
        ungraded:     to_be.(grades.where(grade: nil).group(:year_ce, :semester).count),
        offerings:    offerings.group(*sem_group).count,
        sections:     sections.group(*sem_group).count,
        time_slots:   slots.group(*sem_group).count
      }
    end

    def build_row(term, counts)
      year_be, sem = term
      {
        term:         "#{year_be}/#{sem}",
        # cohorts arrive in semester 1; other semesters are not applicable
        new_students: sem == 1 ? counts[:new_students].fetch(year_be, 0) : BLANK,
        grades:       counts[:grades].fetch(term, 0),
        ungraded:     counts[:ungraded].fetch(term, 0),
        offerings:    counts[:offerings].fetch(term, 0),
        sections:     counts[:sections].fetch(term, 0),
        time_slots:   counts[:time_slots].fetch(term, 0)
      }
    end

    # Era rule + flags, in place. A dataset's era starts at its earliest
    # non-zero term; before that the dataset simply wasn't tracked, so the
    # cell is BLANK, not red. Within the era: 0 -> red; below LOW_RATIO of
    # the median of non-zero same-semester-number counts in OTHER years ->
    # yellow (summers compare only with summers).
    def apply_flags!(rows, terms)
      FLAGGED_KEYS.each { |key| flag_column!(key, rows, terms) }
      # :ungraded is a sub-count of :grades — blank it outside the grades era.
      rows.each { |row| row[:ungraded] = BLANK if row[:grades] == BLANK }
    end

    def flag_column!(key, rows, terms)
      applicable = rows.each_index.select { |i| rows[i][key] != BLANK }
      era_start = applicable.select { |i| rows[i][key].positive? }
                            .map { |i| terms[i] }.min
      if era_start.nil? # dataset has no data at all: nothing is "missing"
        applicable.each { |i| rows[i][key] = BLANK }
        return
      end
      in_era, pre_era = applicable.partition { |i| (terms[i] <=> era_start) >= 0 }
      pre_era.each { |i| rows[i][key] = BLANK }
      in_era.each do |i|
        value = rows[i][key]
        if value.zero?
          rows[i][:"#{key}_class"] = MISSING_CLASS
          next
        end
        peers = in_era.select do |j|
          j != i && terms[j][1] == terms[i][1] && rows[j][key].positive?
        end
        peer_median = median(peers.map { |j| rows[j][key] })
        rows[i][:"#{key}_class"] = LOW_CLASS if peer_median && value < LOW_RATIO * peer_median
      end
    end

    def median(values)
      return nil if values.empty?
      sorted = values.sort
      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Legend sentence + the curriculum diagnostic: a program revision with no
    # program_courses rows means a curriculum arrived but its courses were
    # never imported/linked. The "0000" placeholder program is exempt.
    def summary_text(rows)
      parts = ["Coverage for #{rows.size} term(s). " \
               "Red = missing, yellow = low vs. same-semester median, — = predates the dataset."]
      unlinked = Program.where.missing(:program_courses).includes(:program_group)
                        .reject(&:placeholder?)
                        .sort_by { |p| [-p.year_started_be, p.program_code] }
      if unlinked.any?
        labels = unlinked.map { |p| "#{p.program_group.code} #{p.year_started_be} (#{p.program_code})" }
        parts << "⚠ Programs with no courses linked: #{labels.join(', ')}."
      end
      parts.join(" ")
    end
  end
end
```

- [ ] **Step 2: Register it**

In `app/services/reports/registry.rb`:

SECTIONS — add one entry (comma on the previous line):

```ruby
    SECTIONS = {
      courses:    "Courses",
      students:   "Students",
      curriculum: "Curriculum",
      thesis:     "Thesis",
      admin:      "Data"
    }.freeze
```

REPORTS — add one line (comma on the previous line):

```ruby
      Reports::StaffCoursesByYear,
      Reports::DataCoverage
```

- [ ] **Step 3: Smoke-test against the dev database**

Run:

```bash
bin/rails runner 'r = Reports::DataCoverage.new({}).run; puts r.summary; puts r.columns.map { |c| c[:label] }.join(" | "); r.rows.first(8).each { |row| puts [:term, :new_students, :grades, :ungraded, :offerings, :sections, :time_slots].map { |k| row[k] }.join(" | ") }'
```

Expected: the summary legend line, the 7 column labels, then up to 8 term rows newest-first (dev DB has real data: grade terms back many years, schedule terms for 2568–2569). Old terms must show `—` in Offerings/Sections/Time Slots (pre-schedule-era), not 0. No exception.

Then the toggle:

```bash
bin/rails runner 'a = Reports::DataCoverage.new({}).run.rows; b = Reports::DataCoverage.new("program_courses_only" => "1").run.rows; ra = a.find { |r| r[:grades].is_a?(Integer) && r[:grades] > 0 }; rb = b.find { |r| r[:term] == ra[:term] }; puts "all=#{ra[:grades]} curriculum-only=#{rb[:grades]}"'
```

Expected: two integers with `curriculum-only <= all` (strictly smaller if that term has gen-ed grades).

Also confirm the registry: `bin/rails runner 'puts Reports::Registry.find("data_coverage")'` → `Reports::DataCoverage`.

- [ ] **Step 4: Commit**

```bash
hg add app/services/reports/data_coverage.rb
hg commit app/services/reports/data_coverage.rb app/services/reports/registry.rb -m "Data-coverage report: spot terms whose import or scrape was missed

Three ingestion paths must each run every semester, but nothing surfaced
a missed term: data_imports rows don't record which term a file covered,
and term data also arrives via the CuGetReg scraper and ChulaBooster
sync, so auditing runs can't answer it. This audits data presence
instead: one row per term, counts for new students / grades / schedule,
red for zero within a dataset's era, yellow for suspiciously low vs. the
same-semester median (summers compare with summers), and a dash before a
dataset's era so pre-schedule history isn't a wall of false red. A
checkbox restricts counts to curriculum courses (any program_courses
link), since gen-ed rows can mask missing department data. The summary
also flags program revisions with zero linked courses — a new curriculum
whose course list was never imported. Ungraded is informational only
(zero ungraded is good, so it is never flagged)."
```

---

### Task 3: Cross-link from `/data_sources` + backlog updates

Backlog item 1 fires (new report → entity/page cross-links) and item 2 fires (new report → overlap review). Both are applied here, per `docs/backlog.md`'s standing instructions.

**Files:**
- Modify: `app/views/data_sources/index.html.haml`
- Modify: `docs/backlog.md`

**Interfaces:**
- Consumes: report key `"data_coverage"` (Task 2); route helper `report_path` (existing `resources :reports`).
- Produces: nothing downstream.

- [ ] **Step 1: Add the link to the Data Sources intro**

In `app/views/data_sources/index.html.haml`, directly after the existing intro paragraph (`%p.text-body-secondary How data enters cp-api. ...`), at the same indentation, add:

```haml
    %p.text-body-secondary
      To check whether any term's data actually arrived, see the
      = succeed "" do
        = link_to "Data Coverage report", report_path("data_coverage")
      %span<
        &nbsp;— per-term counts for grades, schedule, and new students, with gaps flagged.
```

If the HAML whitespace fights back, this simpler equivalent is fine:

```haml
    %p.text-body-secondary
      To check whether any term's data actually arrived, see the
      #{link_to "Data Coverage report", report_path("data_coverage")} —
      per-term counts for grades, schedule, and new students, with gaps flagged.
```

(Use the second form by default; it renders the link inline inside the sentence.)

- [ ] **Step 2: Extend backlog item 1's seed list**

In `docs/backlog.md`, append to the seed list under section 1 (after the `program_groups/show` bullet):

```markdown
- **data_sources/index** → `data_coverage`: the source docs answer "how does
  data get in"; the report answers "did it actually arrive for each term"
  (per-term counts with gaps flagged). Link added 2026-07-16.
```

- [ ] **Step 3: Add the report to backlog item 2's status list**

Append to the status list under section 2 (after the `semester_grade_distribution, ...` bullet):

```markdown
- `data_coverage` — set/aggregate report (terms × datasets), no single-entity
  anchor. Keep regardless.
```

- [ ] **Step 4: Verify the page renders**

Run:

```bash
bin/rails runner 'app = ActionDispatch::Integration::Session.new(Rails.application); app.get "/data_sources"; puts app.response.status'
```

Expected: `302` (redirect to login — fine, it proves routing/compile). Stronger check: `AUTO_LOGIN=1 bin/rails server -p 3001` in background, then `curl -s http://localhost:3001/data_sources | grep -o "Data Coverage report"` → `Data Coverage report`. Kill the server after.

- [ ] **Step 5: Commit**

```bash
hg commit app/views/data_sources/index.html.haml docs/backlog.md -m "Cross-link Data Sources page to the data-coverage report

Backlog item 1 (entity page -> report cross-links) fires for the new
data_coverage report: /data_sources explains how data gets in, and the
natural next question — did it actually arrive for each term — is what
the report answers. Also records the item-2 overlap verdict: pure
set/aggregate report, no entity anchor, keep regardless."
```

---

### Task 4: Tests (unit + system)

Pre-agreed in the spec's Testing section. The fiddly logic is era detection and median flagging — that's where the unit tests concentrate.

**Files:**
- Create: `test/services/reports/data_coverage_test.rb`
- Create: `test/system/data_coverage_test.rb`

**Interfaces:**
- Consumes: `Reports::DataCoverage` (Task 2) — `new(params_hash).run` → `Result` with `rows` (key `:term` is `"YYYY/S"` B.E.; counts are Integers or `"—"`; flags in `:<key>_class`) and `summary`. Fixtures: `programs(:cp_bachelor)`, `program_groups(:cp_group)`, `users(:admin)` (password `password123`), fixture grades at `year_ce: 2024` (= term 2567), fixture semesters 2568/1 + 2568/2.
- Produces: nothing downstream.

**Testing approach:** this report counts whole tables, so fixture rows would pollute every count. The unit test wipes all term-scoped data in FK order and builds exactly the terms each test needs. Grade uniqueness is per `(student, course, year, semester)`, so N grades in one term = N throwaway courses for one student.

- [ ] **Step 1: Write the unit test**

`test/services/reports/data_coverage_test.rb` — complete file:

```ruby
require "test_helper"

class Reports::DataCoverageTest < ActiveSupport::TestCase
  # The report counts whole tables, so fixture rows would pollute every
  # assertion. Wipe term-scoped data (FK order: grades reference sections;
  # slots/teachings reference sections; sections reference offerings;
  # offerings and scrapes reference semesters) and build controlled terms.
  setup do
    Grade.delete_all
    TimeSlot.delete_all
    Teaching.delete_all
    Section.delete_all
    CourseOffering.delete_all
    Scrape.delete_all
    Semester.delete_all
    Student.delete_all
    @seq = 0
    @student = Student.create!(
      student_id: "9900000001", first_name: "T", last_name: "S",
      first_name_th: "ท", last_name_th: "ส", admission_year_be: 2500,
      status: "active", program: programs(:cp_bachelor)
    )
  end

  test "era rule: pre-era cells blank, zero within era red" do
    Semester.create!(year_be: 2565, semester_number: 1)  # before any grades
    Semester.create!(year_be: 2567, semester_number: 1)  # inside grades era, no grades
    make_grades(5, 2566, 1)
    make_grades(5, 2568, 1)

    rows = run_rows
    assert_equal ["2568/1", "2567/1", "2566/1", "2565/1"], rows.map { |r| r[:term] }

    pre_era = row(rows, "2565/1")
    assert_equal "—", pre_era[:grades]
    assert_nil pre_era[:grades_class]
    assert_equal "—", pre_era[:ungraded], "ungraded blanks alongside grades"

    missing = row(rows, "2567/1")
    assert_equal 0, missing[:grades]
    assert_equal "report-cell-missing", missing[:grades_class]

    ok = row(rows, "2566/1")
    assert_equal 5, ok[:grades]
    assert_nil ok[:grades_class]
  end

  test "a dataset with no data at all is all-blank, never red" do
    make_grades(3, 2566, 1)  # grades exist; schedule tables stay empty
    r = row(run_rows, "2566/1")
    assert_equal "—", r[:offerings]
    assert_nil r[:offerings_class]
  end

  test "low count vs same-semester median is yellow; summers compare with summers" do
    make_grades(10, 2564, 1)
    make_grades(10, 2565, 1)
    make_grades(10, 2566, 1)
    make_grades(4,  2567, 1)  # 4 < 0.5 * median(10,10,10) -> yellow
    make_grades(2,  2566, 3)  # small summers
    make_grades(2,  2567, 3)  # peer median 2 -> 2 is NOT < 1 -> no flag

    rows = run_rows
    assert_equal "report-cell-low", row(rows, "2567/1")[:grades_class]
    assert_nil row(rows, "2564/1")[:grades_class],
               "healthy year must not be flagged (median of others includes the low year)"
    assert_nil row(rows, "2566/3")[:grades_class],
               "summer must be judged against summers, not semester-1 medians"
    assert_nil row(rows, "2567/3")[:grades_class]
  end

  test "median of peers excludes zero terms so past missed terms don't drag the baseline" do
    make_grades(10, 2564, 1)
    make_grades(10, 2565, 1)
    Semester.create!(year_be: 2566, semester_number: 1)  # missed term: 0 grades
    make_grades(10, 2567, 1)

    rows = run_rows
    assert_equal "report-cell-missing", row(rows, "2566/1")[:grades_class]
    assert_nil row(rows, "2567/1")[:grades_class],
               "10 vs median(10, 10) — the zero term must not lower the median"
  end

  test "new students count on semester-1 rows only" do
    3.times { |i| make_student("66000000#{i}", 2566) }
    make_grades(1, 2566, 1)
    make_grades(1, 2566, 2)

    rows = run_rows
    assert_equal 3, row(rows, "2566/1")[:new_students]
    assert_equal "—", row(rows, "2566/2")[:new_students]
    assert_nil row(rows, "2566/2")[:new_students_class]
  end

  test "ungraded counts blank grades and is never flagged" do
    make_grades(2, 2566, 1)
    course = make_course
    Grade.create!(student: @student, course: course, year_ce: 2566 - 543,
                  semester: 1, grade: nil, source: "imported")

    r = row(run_rows, "2566/1")
    assert_equal 3, r[:grades]
    assert_equal 1, r[:ungraded]
    assert_nil r[:ungraded_class]
  end

  test "program-courses-only toggle restricts counts to curriculum-linked courses" do
    linked = make_course
    ProgramCourse.create!(program: programs(:cp_bachelor), course: linked)
    gened = make_course
    Grade.create!(student: @student, course: linked, year_ce: 2566 - 543,
                  semester: 1, grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: @student, course: gened, year_ce: 2566 - 543,
                  semester: 1, grade: "A", grade_weight: 4.0, source: "imported")
    sem = Semester.create!(year_be: 2566, semester_number: 1)
    [linked, gened].each do |c|
      off = CourseOffering.create!(course: c, semester: sem, status: "confirmed")
      Section.create!(course_offering: off, section_number: 1)
    end

    all_rows      = run_rows
    filtered_rows = Reports::DataCoverage.new("program_courses_only" => "1").run.rows

    assert_equal 2, row(all_rows, "2566/1")[:grades]
    assert_equal 1, row(filtered_rows, "2566/1")[:grades]
    assert_equal 2, row(all_rows, "2566/1")[:offerings]
    assert_equal 1, row(filtered_rows, "2566/1")[:offerings]
    assert_equal 1, row(filtered_rows, "2566/1")[:sections]
  end

  test "summary flags program revisions with no linked courses, never the placeholder" do
    make_grades(1, 2566, 1)
    Program.create!(program_code: "9999", year_started_be: 2571,
                    program_group: program_groups(:cp_group))
    Program.placeholder  # ensure the 0000 placeholder exists

    summary = Reports::DataCoverage.new({}).run.summary
    assert_includes summary, "CP 2571 (9999)"
    assert_not_includes summary, "(0000)"
  end

  private

  def run_rows
    Reports::DataCoverage.new({}).run.rows
  end

  def row(rows, term)
    rows.find { |r| r[:term] == term } || flunk("no row for term #{term}")
  end

  def make_course
    @seq += 1
    Course.create!(course_no: "99#{format('%05d', @seq)}", name: "Coverage #{@seq}",
                   revision_year_be: 2565)
  end

  # N grades in one term = N throwaway courses for one student (grade
  # uniqueness is per student+course+term).
  def make_grades(count, year_be, semester)
    count.times do
      Grade.create!(student: @student, course: make_course, year_ce: year_be - 543,
                    semester: semester, grade: "A", grade_weight: 4.0,
                    credits_grant: 3, source: "imported")
    end
  end

  def make_student(id, admission_year_be)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: admission_year_be,
                    status: "active", program: programs(:cp_bachelor))
  end
end
```

- [ ] **Step 2: Run the unit test**

Run: `bin/rails test test/services/reports/data_coverage_test.rb`
Expected: `8 runs, 0 failures, 0 errors`. If a `delete_all` hits a foreign-key error, fix the deletion ORDER in setup (children before parents), not by switching to `destroy_all`.

- [ ] **Step 3: Write the system test**

`test/system/data_coverage_test.rb` — complete file:

```ruby
require "application_system_test_case"

class DataCoverageTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "coverage report renders the matrix with flagged cells" do
    sign_in users(:admin)
    visit report_path("data_coverage")
    click_on "Run report"

    assert_text "2567/1"          # fixture grades live at year_ce 2024
    assert_text(/Grades/i)
    # Fixture semesters 2568/1 + 2568/2 exist with zero grades -> red cells
    # inside the grades era.
    assert_selector "td.report-cell-missing"
  end

  test "program-courses-only checkbox round-trips" do
    sign_in users(:admin)
    visit report_path("data_coverage")
    check "program_courses_only"
    click_on "Run report"

    assert_selector "input#program_courses_only[checked]"
    assert_text "2567/1"
  end

  test "appears on the reports index under Data" do
    sign_in users(:admin)
    visit reports_path

    assert_text "Data"
    assert_text "Which terms are missing data"
  end
end
```

- [ ] **Step 4: Run the system test**

Run: `bin/rails test:system test/system/data_coverage_test.rb`
Expected: `3 runs, 0 failures, 0 errors` (headless Firefox; takes ~30–60s). If `assert_selector "input#program_courses_only[checked]"` fails on attribute matching, use `assert_selector "input#program_courses_only"` + `assert find("#program_courses_only").checked?` instead.

- [ ] **Step 5: Run the full non-system suite to catch regressions**

Run: `bin/rails test`
Expected: 0 failures, 0 errors (the two touched partials are shared by all reports — this catches breakage in the other seven).

- [ ] **Step 6: Commit**

```bash
hg add test/services/reports/data_coverage_test.rb test/system/data_coverage_test.rb
hg commit test/services/reports/data_coverage_test.rb test/system/data_coverage_test.rb -m "Tests for the data-coverage report

The report's era detection and median flagging are easy to get subtly
wrong (zero terms dragging the baseline, summers judged against
semester-1 medians, pre-era history flagged red), so the unit tests pin
each of those behaviours with controlled terms on a wiped slate —
fixture rows would pollute whole-table counts. System tests cover the
happy path: matrix renders with red cells for the fixture's grade-less
2568 semesters, the checkbox round-trips, and the report is listed
under Data."
```

---

### Task 5: Visual verification (screenshots for the maintainer)

The maintainer approves UI changes only after seeing rendered output. No commit in this task — its deliverable is screenshots presented in the conversation.

**Files:** none (read-only verification).

**Interfaces:**
- Consumes: the finished report at `/reports/data_coverage` (Tasks 1–3); dev DB with real data; `AUTO_LOGIN` env var (auto-authenticates as user ID 1).

- [ ] **Step 1: Build CSS and start the dev server**

```bash
bin/rails dartsass:build
AUTO_LOGIN=1 bin/rails server -p 3001
```

(Server in the background; port 3001 avoids clashing with a running `bin/dev`.)

- [ ] **Step 2: Screenshot the report (default and filtered)**

```bash
mkdir -p /tmp/claude-1002/-home-dae-cp-api/16dbdbd9-5bd2-4a35-9f02-f7435b480afc/scratchpad/shots
firefox --headless --window-size=1600,1400 --screenshot /tmp/claude-1002/-home-dae-cp-api/16dbdbd9-5bd2-4a35-9f02-f7435b480afc/scratchpad/shots/coverage-all.png "http://localhost:3001/reports/data_coverage?run=1"
firefox --headless --window-size=1600,1400 --screenshot /tmp/claude-1002/-home-dae-cp-api/16dbdbd9-5bd2-4a35-9f02-f7435b480afc/scratchpad/shots/coverage-filtered.png "http://localhost:3001/reports/data_coverage?run=1&program_courses_only=1"
```

- [ ] **Step 3: Inspect the screenshots (Read the PNGs) and check:**

- Red cells appear only where a term inside a dataset's era has zero (e.g. grade-less scraped future terms), not across all of history.
- Old terms show `—` in the three schedule columns (pre-era), not red.
- Yellow cells, if any, look plausible (genuinely low terms).
- The legend/summary line renders, including any ⚠ curriculum warning.
- Red/yellow tints are visible but not glaring against the dark theme.

- [ ] **Step 4: Present the screenshots to the maintainer**

Show both PNGs, note anything surprising in the real data (e.g. which terms are flagged), and stop for feedback. Kill the background server.

---

## Self-Review (performed at planning time)

- **Spec coverage:** report class + registry (Task 2), rows/columns/era/flagging/toggle/diagnostic (Task 2), `:boolean` param + `class_key` + SCSS (Task 1), CSV unaffected (verified — exporter reads only `col[:key]`), backlog items 1 & 2 + data_sources link (Task 3), testing section (Task 4). One deliberate refinement vs. spec: the spec's flagging section didn't exempt **Ungraded**, but red-on-zero is backwards for it (zero ungraded is good) — it is informational-only, and blanks alongside Grades outside the grades era. Flagged to the maintainer in the plan summary.
- **Placeholder scan:** none — all steps carry complete code/commands.
- **Type consistency:** row keys (`:term, :new_students, :grades, :ungraded, :offerings, :sections, :time_slots`, `:<key>_class`), CSS class strings, report key `"data_coverage"`, and param `"program_courses_only" => "1"` are consistent across Tasks 1–5.
