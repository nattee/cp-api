# Grade Distribution & Cohort GPA Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Course grade distribution and cohort GPA reports (spec: `docs/superpowers/specs/2026-07-08-grade-reports-design.md`), on the web report framework and as LINE bot tools, backed by shared `GradeStats` services.

**Architecture:** Three `GradeStats::*` query objects hold all the math. Two thin `Reports::*` classes expose them on the web (existing Registry framework: form, table, CSV for free) with charts via a new optional `chart` field on `Reports::Result`. Two thin `Line::Tools::*` classes expose them on LINE, returning compact JSON for the LLM.

**Tech Stack:** Ruby 3.4 / Rails 8.1, MySQL 8 (has `STDDEV_SAMP`), HAML, Stimulus + Chart.js (UMD), Minitest.

## Global Constraints

- **Mercurial, not git.** Commit with `hg commit <explicit files> -m "..."` — always name the files (the repo has unrelated dirty changes). Commit messages lead with WHY (first paragraph = motivation), then what.
- **Tests are written AFTER the implementation works** (project preference; spec Section 4). Implementation tasks end with a `bin/rails runner` spot check, not a test. Test tasks are 9–12.
- **No new fixtures.** LINE lookup-tool tests assert exact fixture counts (e.g. "all courses == 3"). All test data is created in each test's `setup` (isolated records — see `test/services/reports/failing_students_test.rb` for the canonical pattern).
- **Courses aggregate by `course_no`, never by revision.** All revisions of a course count together everywhere.
- **GPA = weighted grades only** (`grade_weight` NOT NULL, i.e. A–F). S/U/W/etc. appear in distribution counts, never in GPA.
- **All GPA statistics round to 2 decimals inside `GradeStats`** so web and LINE show identical numbers.
- **SD is sample SD** (n−1). MySQL `STDDEV_SAMP` matches; it returns NULL for n=1, which maps to `nil`.
- **Year conventions:** `Grade#year_ce` is C.E. Web report params are B.E. (convert with −543, like `Reports::FailingStudents`). LINE tool params accept either era; values < 2400 are C.E. `Student#admission_year_be` is B.E.
- **Dev-DB spot checks:** the development DB holds real synced data — `2110327` in `year_ce: 2025, semester: 2` and the CP cohort `admission_year_be: 2565` should return non-empty results.

---

### Task 1: `GradeStats::Stats` + `GradeStats::CourseDistribution`

**Files:**
- Create: `app/services/grade_stats/stats.rb`
- Create: `app/services/grade_stats/course_distribution.rb`

**Interfaces:**
- Consumes: `Grade` (`year_ce`, `semester`, `grade`, `grade_weight`, `Grade::GRADES`), `Course` (`course_no`).
- Produces:
  - `GradeStats::Stats.mean(floats) -> Float|nil` (2dp), `GradeStats::Stats.sample_sd(floats) -> Float|nil` (2dp, nil when n<2), `GradeStats::Stats.aggregate(floats) -> {n:, avg:, sd:, min:, max:, minus2sd:, plus2sd:}` (all 2dp, nils when empty/n<2).
  - `GradeStats::CourseDistribution.call(course_no:, year_ce:, semester:) -> Hash` and `call(course_no:, year_ce:) -> Array<Hash>` (one per term). Hash shape: `{course_no:, year_ce:, semester:, total:, counts: {"A"=>2,...}, gpa: {n:, mean:, sd:}}` — `counts` keyed in `Grade::GRADES` order, present grades only.

- [ ] **Step 1: Create `app/services/grade_stats/stats.rb`**

```ruby
module GradeStats
  # Shared numeric helpers for the grade statistics services. All GPA numbers
  # are rounded here (2 decimals) so web and LINE always show identical values.
  # SD is sample SD (n-1 denominator); nil when there are fewer than 2 values.
  module Stats
    module_function

    def mean(values)
      return nil if values.empty?
      (values.sum.to_f / values.size).round(2)
    end

    def sample_sd(values)
      raw_sample_sd(values)&.round(2)
    end

    # Full aggregate for cohort statistics: n, avg, sd, min, max, avg∓2sd.
    def aggregate(values)
      return { n: 0, avg: nil, sd: nil, min: nil, max: nil, minus2sd: nil, plus2sd: nil } if values.empty?

      m  = values.sum.to_f / values.size
      sd = raw_sample_sd(values)
      {
        n: values.size,
        avg: m.round(2),
        sd: sd&.round(2),
        min: values.min.round(2),
        max: values.max.round(2),
        minus2sd: sd ? (m - 2 * sd).round(2) : nil,
        plus2sd:  sd ? (m + 2 * sd).round(2) : nil
      }
    end

    def raw_sample_sd(values)
      return nil if values.size < 2
      m = values.sum.to_f / values.size
      Math.sqrt(values.sum { |v| (v - m)**2 } / (values.size - 1))
    end
  end
end
```

- [ ] **Step 2: Create `app/services/grade_stats/course_distribution.rb`**

```ruby
module GradeStats
  # Grade distribution + course GPA for one course in one term — or one result
  # per term of the year when semester is nil (used by the LINE tool when the
  # user doesn't name a term). Aggregates by course_no: all curriculum
  # revisions of the course count together.
  # See docs/superpowers/specs/2026-07-08-grade-reports-design.md.
  class CourseDistribution
    def self.call(course_no:, year_ce:, semester: nil)
      return term_result(course_no, year_ce, semester) if semester

      base_scope(course_no, year_ce).distinct.pluck(:semester).sort
                                    .map { |s| term_result(course_no, year_ce, s) }
    end

    def self.term_result(course_no, year_ce, semester)
      scope = base_scope(course_no, year_ce).where(semester: semester)

      raw = scope.where.not(grade: [ nil, "" ]).group(:grade).count
      counts = Grade::GRADES.each_with_object({}) { |g, h| h[g] = raw[g] if raw[g] }
      weights = scope.where.not(grade_weight: nil).pluck(:grade_weight).map(&:to_f)

      {
        course_no: course_no,
        year_ce: year_ce,
        semester: semester,
        total: counts.values.sum,
        counts: counts,
        gpa: { n: weights.size, mean: Stats.mean(weights), sd: Stats.sample_sd(weights) }
      }
    end
    private_class_method :term_result

    def self.base_scope(course_no, year_ce)
      Grade.joins(:course).where(courses: { course_no: course_no }, year_ce: year_ce)
    end
    private_class_method :base_scope
  end
end
```

- [ ] **Step 3: Spot-check against the dev DB**

Run:
```bash
bin/rails runner 'pp GradeStats::CourseDistribution.call(course_no: "2110327", year_ce: 2025, semester: 2)'
bin/rails runner 'pp GradeStats::CourseDistribution.call(course_no: "2110327", year_ce: 2024)'
```
Expected: first prints one hash with non-empty `counts` in A→X order and a `gpa` hash with 2-decimal `mean`/`sd`; second prints an array with one hash per term that has grades. `total` equals the sum of `counts` values.

- [ ] **Step 4: Commit**

```bash
hg add app/services/grade_stats/stats.rb app/services/grade_stats/course_distribution.rb
hg commit app/services/grade_stats/stats.rb app/services/grade_stats/course_distribution.rb -m "Staff need grade statistics (distribution + course GPA) answered identically
on the web and on LINE, so the math must live in services both surfaces share
rather than in either surface's layer.

Add GradeStats::Stats (mean / sample SD / aggregate, all rounded to 2dp in one
place) and GradeStats::CourseDistribution (per-term distribution and GPA for
one course_no, revisions merged; nil semester = every term of the year)."
```

---

### Task 2: `GradeStats::SemesterCourseTable`

**Files:**
- Create: `app/services/grade_stats/semester_course_table.rb`

**Interfaces:**
- Consumes: `GradeStats::Stats` (rounding convention only — SQL does the math here), `ProgramGroup`, `Course.joins(program_courses: { program: :program_group })`.
- Produces: `GradeStats::SemesterCourseTable.call(program_group:, year_ce:, semester:) -> {grade_columns: ["A","B+",...], rows: [{course_no:, name:, total:, counts: {...}, gpa: {n:, mean:, sd:}}]}` — `grade_columns` is the `Grade::GRADES`-ordered union of grades present; rows sorted by `course_no`; `name` from the latest revision.

- [ ] **Step 1: Create `app/services/grade_stats/semester_course_table.rb`**

```ruby
module GradeStats
  # One row per course (keyed by course_no, revisions merged) in a program
  # group's curriculum that has grades in the given term. Backs the
  # "grade distribution by course" web report.
  class SemesterCourseTable
    def self.call(program_group:, year_ce:, semester:)
      course_nos = Course.joins(program_courses: { program: :program_group })
                         .where(program_groups: { id: program_group.id })
                         .distinct.pluck(:course_no)

      scope = Grade.joins(:course)
                   .where(courses: { course_no: course_nos },
                          year_ce: year_ce, semester: semester)

      counts = scope.where.not(grade: [ nil, "" ]).group("courses.course_no", :grade).count
      gpa_by_no = scope.where.not(grade_weight: nil)
                       .group("courses.course_no")
                       .pluck(Arel.sql("courses.course_no, COUNT(*), " \
                                       "AVG(grades.grade_weight), STDDEV_SAMP(grades.grade_weight)"))
                       .index_by(&:first)

      present_nos = counts.keys.map(&:first).uniq.sort
      # index_by keeps the last occurrence, so ascending revision order means
      # the latest revision's name wins.
      names = Course.where(course_no: present_nos).order(:revision_year_be).index_by(&:course_no)
      grade_columns = Grade::GRADES.select { |g| counts.keys.any? { |_, grade| grade == g } }

      rows = present_nos.map do |no|
        by_grade = Grade::GRADES.each_with_object({}) do |g, h|
          c = counts[[ no, g ]]
          h[g] = c if c
        end
        _, n, avg, sd = gpa_by_no[no]
        {
          course_no: no,
          name: names[no]&.name,
          total: by_grade.values.sum,
          counts: by_grade,
          gpa: { n: n.to_i, mean: avg&.to_f&.round(2), sd: sd&.to_f&.round(2) }
        }
      end

      { grade_columns: grade_columns, rows: rows }
    end
  end
end
```

- [ ] **Step 2: Spot-check against the dev DB**

Run:
```bash
bin/rails runner 'r = GradeStats::SemesterCourseTable.call(program_group: ProgramGroup.find_by(code: "CP"), year_ce: 2025, semester: 1); puts r[:grade_columns].inspect; puts r[:rows].size; pp r[:rows].first(3)'
```
Expected: `grade_columns` is a subset of `Grade::GRADES` in that order; dozens of rows sorted by course_no; each row's `total` equals the sum of its `counts`; `gpa.mean` between 0 and 4 with 2 decimals.

- [ ] **Step 3: Commit**

```bash
hg add app/services/grade_stats/semester_course_table.rb
hg commit app/services/grade_stats/semester_course_table.rb -m "The department needs a per-semester overview of how every course in a
program's curriculum was graded, which no single existing query provides.

Add GradeStats::SemesterCourseTable: two GROUP BY queries keyed on
courses.course_no (so curriculum revisions merge), returning per-course grade
counts plus GPA mean/SD (STDDEV_SAMP = sample SD, NULL for n=1) and the
ordered union of grades present."
```

---

### Task 3: `GradeStats::CohortGpa`

**Files:**
- Create: `app/services/grade_stats/cohort_gpa.rb`

**Interfaces:**
- Consumes: `GradeStats::Stats.aggregate`, `Student.joins(program: :program_group)`, `Student#admission_year_be`.
- Produces: `GradeStats::CohortGpa.call(program_group:, admission_year_be:) -> {terms: [{year_ce:, semester:, gps: AGG, gpax: AGG}]}` where `AGG = {n:, avg:, sd:, min:, max:, minus2sd:, plus2sd:}`. Terms chronological. GPS n = students with ≥1 weighted grade that term; GPAX n = students with ≥1 weighted grade up to and including that term (a gap-semester student keeps their GPAX).

- [ ] **Step 1: Create `app/services/grade_stats/cohort_gpa.rb`**

```ruby
module GradeStats
  # Per-term GPS (term GPA) and GPAX (cumulative GPA) aggregates for one
  # admission cohort of a program group. Computed in Ruby from a single pluck:
  # a cohort is a few hundred students, and per-term cumulative GPA is trivial
  # here but painful in MySQL.
  class CohortGpa
    def self.call(program_group:, admission_year_be:)
      student_ids = Student.joins(program: :program_group)
                           .where(program_groups: { id: program_group.id },
                                  students: { admission_year_be: admission_year_be })
                           .pluck(:id)

      rows = Grade.joins(:course)
                  .where(student_id: student_ids)
                  .where.not(grade_weight: nil)
                  .pluck(:student_id, :year_ce, :semester, :grade_weight, "courses.credits")

      by_term = rows.group_by { |_, y, s, _, _| [ y, s ] }
      # Running per-student totals across terms, for GPAX.
      cumulative = Hash.new { |h, k| h[k] = { points: 0.0, credits: 0.0 } }

      terms = by_term.keys.sort.map do |year_ce, semester|
        per_student = by_term[[ year_ce, semester ]].group_by(&:first)

        gps_values = per_student.filter_map do |_, grades|
          gpa_of(points(grades), credits(grades))
        end

        per_student.each do |sid, grades|
          cumulative[sid][:points]  += points(grades)
          cumulative[sid][:credits] += credits(grades)
        end

        gpax_values = cumulative.values.filter_map { |t| gpa_of(t[:points], t[:credits]) }

        { year_ce: year_ce, semester: semester,
          gps: Stats.aggregate(gps_values), gpax: Stats.aggregate(gpax_values) }
      end

      { terms: terms }
    end

    def self.points(grades)
      grades.sum { |_, _, _, w, c| w.to_f * c.to_f }
    end
    private_class_method :points

    def self.credits(grades)
      grades.sum { |_, _, _, _, c| c.to_f }
    end
    private_class_method :credits

    def self.gpa_of(points, credits)
      credits.zero? ? nil : points / credits
    end
    private_class_method :gpa_of
  end
end
```

- [ ] **Step 2: Spot-check against the dev DB**

Run:
```bash
bin/rails runner 'r = GradeStats::CohortGpa.call(program_group: ProgramGroup.find_by(code: "CP"), admission_year_be: 2565); r[:terms].each { |t| puts "#{t[:year_ce]}/#{t[:semester]}  gps n=#{t[:gps][:n]} avg=#{t[:gps][:avg]}  gpax n=#{t[:gpax][:n]} avg=#{t[:gpax][:avg]}" }'
```
Expected: chronological terms starting 2022/1; GPS n ≈ cohort size each term; GPAX n never decreases; all averages in 0–4 with 2 decimals; GPAX avg moves smoothly (cumulative damping) while GPS avg swings more.

- [ ] **Step 3: Commit**

```bash
hg add app/services/grade_stats/cohort_gpa.rb
hg commit app/services/grade_stats/cohort_gpa.rb -m "Staff want to see how an admission cohort performs over time - per-semester
GPA aggregates, not individual transcripts - and cumulative GPA per term is
awkward to express in MySQL but trivial in Ruby at cohort scale.

Add GradeStats::CohortGpa: single pluck of the cohort's weighted grades, then
per-student GPS (term) and GPAX (running) per semester, aggregated as
n/avg/sd/min/max/avg-+2sd via GradeStats::Stats."
```

---

### Task 4: Reports framework extensions (chart support + program-group param)

**Files:**
- Modify: `app/services/reports/result.rb`
- Modify: `app/services/reports/base.rb` (the private `result` helper, lines 52–54)
- Modify: `app/views/reports/show.html.haml`
- Create: `app/views/reports/_chart.html.haml`
- Modify: `app/views/reports/_form.html.haml` (the `case p[:type]` block)

**Interfaces:**
- Consumes: existing `Reports::Result`, `reports/show` render flow, `chart_controller.js` (`data-chart-type-value` / `data-chart-data-value` / canvas target).
- Produces: `Reports::Base#result(columns:, rows:, summary: nil, chart: nil)`; `Reports::Result#chart` returning `{type: String, data: Hash, height: Integer}` or nil; `:program_group` param type whose submitted value is a ProgramGroup **code** string (e.g. `"CP"`).

- [ ] **Step 1: Add `chart` to `Reports::Result`**

Replace the class body of `app/services/reports/result.rb` with:

```ruby
module Reports
  # Structured return value for every report. Both the web table renderer and
  # (future) the LINE JSON serializer consume this — never HTML, never prose.
  class Result
    attr_reader :columns, :rows, :summary, :chart

    # columns: [{ key: :student_id, label: "Student ID" }, ...]
    # rows:    [{ student_id: "65...", name: "...", ... }, ...]  (keyed by column key)
    # summary: short human sentence, or nil
    # chart:   optional { type:, data:, height: } rendered above the table by
    #          reports/_chart via chart_controller; nil = table only
    def initialize(columns:, rows:, summary: nil, chart: nil)
      @columns = columns
      @rows = rows
      @summary = summary
      @chart = chart
    end

    def empty?
      rows.empty?
    end
  end
end
```

- [ ] **Step 2: Thread `chart:` through `Reports::Base#result`**

In `app/services/reports/base.rb`, replace:

```ruby
    def result(columns:, rows:, summary: nil)
      Reports::Result.new(columns: columns, rows: rows, summary: summary)
    end
```

with:

```ruby
    def result(columns:, rows:, summary: nil, chart: nil)
      Reports::Result.new(columns: columns, rows: rows, summary: summary, chart: chart)
    end
```

- [ ] **Step 3: Create `app/views/reports/_chart.html.haml`**

```haml
-# app/views/reports/_chart.html.haml
-# Renders @result.chart ({ type:, data:, height: }) via chart_controller.
.card.mb-3
  .card-body.p-3
    %div{"data-controller" => "chart",
         "data-chart-type-value" => @result.chart[:type],
         "data-chart-data-value" => @result.chart[:data].to_json,
         style: "position: relative; height: #{@result.chart[:height] || 320}px;"}
      %canvas{"data-chart-target" => "canvas"}
```

- [ ] **Step 4: Render the chart in `app/views/reports/show.html.haml`**

Replace:

```haml
- if @result
  = render "result_table"
```

with:

```haml
- if @result
  - if @result.chart
    = render "chart"
  = render "result_table"
```

- [ ] **Step 5: Add the `:program_group` param type to `app/views/reports/_form.html.haml`**

Insert after the `- when :semester_record` branch (keep alignment with the surrounding `when`s):

```haml
      - when :program_group
        = select_tag p[:name], options_for_select(ProgramGroup.order(:code).map { |g| [g.code, g.code] }, params[p[:name]]), include_blank: true, class: "form-select"
```

- [ ] **Step 6: Verify nothing broke**

Run: `bin/rails test test/services/reports test/controllers 2>&1 | tail -5`
Expected: same pass/fail state as before this task (all green); existing reports never pass `chart:` so behavior is unchanged.

- [ ] **Step 7: Commit**

```bash
hg add app/views/reports/_chart.html.haml
hg commit app/services/reports/result.rb app/services/reports/base.rb app/views/reports/show.html.haml app/views/reports/_chart.html.haml app/views/reports/_form.html.haml -m "The upcoming grade reports need a chart above the result table and a
program-group dropdown, and the report framework supported neither.

Extend the framework generically: Reports::Result gains an optional chart
field ({type, data, height}) rendered by a new reports/_chart partial through
the existing chart_controller, and the param form gains a :program_group type
(select of group codes). Reports without charts are unaffected."
```

---

### Task 5: `Reports::SemesterGradeDistribution` + grade colors on horizontal bars

**Files:**
- Create: `app/services/reports/semester_grade_distribution.rb`
- Modify: `app/services/reports/registry.rb` (REPORTS list)
- Modify: `app/javascript/controllers/chart_controller.js` (`horizontalStackedBarConfig`, lines 97–104)

**Interfaces:**
- Consumes: `GradeStats::SemesterCourseTable.call` (Task 2), `Reports::Base` DSL + `result(chart:)` (Task 4), `:program_group` param (value = code string).
- Produces: report key `"semester_grade_distribution"`; chart payload `{labels:, colorBy: "grade", datasets: [{code: "A", data: [...]}]}` for type `horizontal-stacked-bar`; row keys `:course_no, :name, :total, :g_<grade>, :gpa, :sd` (grade keys: downcase, `+`→`p`, e.g. `B+`→`:g_bp`).

- [ ] **Step 1: Create `app/services/reports/semester_grade_distribution.rb`**

```ruby
module Reports
  # "How did each course do this semester?" — one row per course (course_no,
  # revisions merged) with grade counts and course GPA, for one program group.
  class SemesterGradeDistribution < Base
    title    "Grade distribution by course"
    section  :courses
    programs :all
    param    :program_group, :program_group, required: true
    param    :year,          :academic_year, required: true   # B.E. year of the grades
    param    :term,          :term,          required: true

    def run
      group = ProgramGroup.find_by(code: program_group)
      return result(columns: fixed_columns, rows: [], summary: "Unknown program group.") unless group

      # Grades store the academic year in C.E. (Grade#year_ce); input is B.E.
      data = GradeStats::SemesterCourseTable.call(
        program_group: group, year_ce: year.to_i - 543, semester: term.to_i
      )

      grade_cols = data[:grade_columns].map { |g| { key: grade_key(g), label: g } }
      columns = fixed_columns.insert(3, *grade_cols)

      rows = data[:rows].map do |r|
        row = { course_no: r[:course_no], name: r[:name], total: r[:total],
                gpa: r[:gpa][:mean], sd: r[:gpa][:sd] }
        data[:grade_columns].each { |g| row[grade_key(g)] = r[:counts][g] }
        row
      end

      result(
        columns: columns,
        rows: rows,
        summary: "#{rows.size} course(s) with grades in #{year}/#{term} (#{group.code})",
        chart: chart_data(data)
      )
    end

    private

    def fixed_columns
      [ { key: :course_no, label: "Course No" }, { key: :name, label: "Name" },
        { key: :total, label: "N" },
        { key: :gpa, label: "GPA" }, { key: :sd, label: "SD" } ]
    end

    # "B+" -> :g_bp — flat row keys for the generic table/CSV renderers.
    def grade_key(grade)
      :"g_#{grade.downcase.tr('+', 'p')}"
    end

    def chart_data(data)
      return nil if data[:rows].empty?
      {
        type: "horizontal-stacked-bar",
        height: [ data[:rows].size * 24 + 80, 240 ].max,
        data: {
          labels: data[:rows].map { |r| r[:course_no] },
          colorBy: "grade",
          datasets: data[:grade_columns].map do |g|
            { code: g, data: data[:rows].map { |r| r[:counts][g] || 0 } }
          end
        }
      }
    end
  end
end
```

- [ ] **Step 2: Register the report**

In `app/services/reports/registry.rb`, add to the REPORTS array (after `Reports::FailingStudents,`):

```ruby
      Reports::SemesterGradeDistribution,
```

- [ ] **Step 3: Grade colors for horizontal stacked bars**

In `app/javascript/controllers/chart_controller.js`, replace the dataset mapping in `horizontalStackedBarConfig()`:

```js
    const datasets = d.datasets.map((ds, i) => ({
      label: ds.code,
      data: ds.data,
      backgroundColor: STACK_COLORS[i % STACK_COLORS.length],
      borderWidth: 0,
    }))
```

with:

```js
    // colorBy: "grade" — segments are letter grades, so use the fixed
    // GRADE_COLORS map instead of positional STACK_COLORS.
    const datasets = d.datasets.map((ds, i) => ({
      label: ds.code,
      data: ds.data,
      backgroundColor: d.colorBy === "grade"
        ? (GRADE_COLORS[ds.code] || "rgba(150, 150, 150, 0.4)")
        : STACK_COLORS[i % STACK_COLORS.length],
      borderWidth: 0,
    }))
```

- [ ] **Step 4: Verify in the browser**

Run: `AUTO_LOGIN=1 bin/dev`, open `http://localhost:3000/reports`, pick "Grade distribution by course", run with Program group = CP, Year = 2568, Term = First.
Expected: stacked horizontal bar chart (grade-colored segments, one bar per course) above a table whose columns are Course No, Name, N, one column per grade, GPA, SD. CSV export downloads the same columns.

- [ ] **Step 5: Commit**

```bash
hg add app/services/reports/semester_grade_distribution.rb
hg commit app/services/reports/semester_grade_distribution.rb app/services/reports/registry.rb app/javascript/controllers/chart_controller.js -m "First consumer of the grade statistics on the web: staff asked for a
per-semester table of every course's grade counts and GPA, plus a visual
overview, per program.

Add Reports::SemesterGradeDistribution (dynamic grade columns from the data,
GPA/SD from GradeStats::SemesterCourseTable, horizontal stacked-bar chart)
and teach horizontalStackedBarConfig a colorBy:grade mode so segments use the
fixed GRADE_COLORS map instead of positional colors."
```

---

### Task 6: `Reports::CohortGpa` + ±2SD band on the GPA trend chart

**Files:**
- Create: `app/services/reports/cohort_gpa.rb`
- Modify: `app/services/reports/registry.rb` (REPORTS list)
- Modify: `app/javascript/controllers/chart_controller.js` (`gpaTrendConfig`, lines 183–215)

**Interfaces:**
- Consumes: `GradeStats::CohortGpa.call` (Task 3), Task 4 framework extensions.
- Produces: report key `"cohort_gpa"`; `gpa-trend` datasets may carry `role: "band-upper"|"band-lower"` (invisible lines forming a fill band, hidden from legend/tooltip) and `dashed: true` (borderDash); row keys `:term, :n, :gps_avg, :gps_sd, :gps_min, :gps_max, :gps_minus2sd, :gps_plus2sd` and the same six with `gpax_` prefix.

- [ ] **Step 1: Create `app/services/reports/cohort_gpa.rb`**

```ruby
module Reports
  # "How did this class year do each semester?" — per-term GPS and GPAX
  # aggregates for one admission cohort of a program group.
  class CohortGpa < Base
    title    "Cohort GPA by semester"
    section  :students
    programs :all
    param    :program_group,  :program_group, required: true
    param    :admission_year, :academic_year, required: true  # B.E.

    STATS = [ [ :avg, "avg" ], [ :sd, "SD" ], [ :min, "min" ], [ :max, "max" ],
              [ :minus2sd, "−2SD" ], [ :plus2sd, "+2SD" ] ].freeze

    def run
      group = ProgramGroup.find_by(code: program_group)
      return result(columns: columns, rows: [], summary: "Unknown program group.") unless group

      data = GradeStats::CohortGpa.call(program_group: group,
                                        admission_year_be: admission_year.to_i)

      rows = data[:terms].map do |t|
        row = { term: term_label(t), n: t[:gps][:n] }
        STATS.each do |key, _|
          row[:"gps_#{key}"]  = t[:gps][key]
          row[:"gpax_#{key}"] = t[:gpax][key]
        end
        row
      end

      result(
        columns: columns,
        rows: rows,
        summary: "#{group.code} #{admission_year} cohort — #{rows.size} semester(s)",
        chart: chart_data(data)
      )
    end

    private

    def columns
      [ { key: :term, label: "Term" }, { key: :n, label: "N" } ] +
        STATS.map { |key, sub| { key: :"gps_#{key}", label: "GPS #{sub}" } } +
        STATS.map { |key, sub| { key: :"gpax_#{key}", label: "GPAX #{sub}" } }
    end

    # Grades store C.E.; staff read terms in B.E.
    def term_label(t)
      "#{t[:year_ce] + 543}/#{t[:semester]}"
    end

    def chart_data(data)
      return nil if data[:terms].empty?
      {
        type: "gpa-trend",
        height: 320,
        data: {
          labels: data[:terms].map { |t| term_label(t) },
          datasets: [
            { label: "GPS +2SD", data: data[:terms].map { |t| t[:gps][:plus2sd] },  role: "band-upper" },
            { label: "GPS −2SD", data: data[:terms].map { |t| t[:gps][:minus2sd] }, role: "band-lower" },
            { label: "GPS avg",  data: data[:terms].map { |t| t[:gps][:avg] } },
            { label: "GPAX avg", data: data[:terms].map { |t| t[:gpax][:avg] }, dashed: true }
          ]
        }
      }
    end
  end
end
```

- [ ] **Step 2: Register the report**

In `app/services/reports/registry.rb`, add to the REPORTS array (after the Task 5 entry):

```ruby
      Reports::CohortGpa,
```

- [ ] **Step 3: Band + dash support in `gpaTrendConfig()`**

In `app/javascript/controllers/chart_controller.js`, replace the dataset mapping at the top of `gpaTrendConfig()`:

```js
    const datasets = d.datasets.map((ds, i) => ({
      label: ds.label,
      data: ds.data,
      borderColor: LINE_COLORS[i % LINE_COLORS.length],
      backgroundColor: LINE_COLORS[i % LINE_COLORS.length],
      spanGaps: true, // connect across terms a subject wasn't offered
      tension: 0.3,
      borderWidth: 2,
      pointRadius: 3,
      pointHoverRadius: 5,
    }))
```

with:

```js
    const datasets = d.datasets.map((ds, i) => {
      const base = {
        label: ds.label,
        data: ds.data,
        borderColor: LINE_COLORS[i % LINE_COLORS.length],
        backgroundColor: LINE_COLORS[i % LINE_COLORS.length],
        spanGaps: true, // connect across terms a subject wasn't offered
        tension: 0.3,
        borderWidth: 2,
        pointRadius: 3,
        pointHoverRadius: 5,
      }
      // ±2SD band: an invisible upper line, then a lower line filling up to
      // it ("-1" = previous dataset). Band datasets must be adjacent and
      // upper-first; they are hidden from the legend and tooltip.
      if (ds.role === "band-upper") {
        Object.assign(base, { borderWidth: 0, pointRadius: 0, pointHoverRadius: 0, isBand: true })
      } else if (ds.role === "band-lower") {
        Object.assign(base, {
          borderWidth: 0, pointRadius: 0, pointHoverRadius: 0, isBand: true,
          fill: "-1", backgroundColor: "rgba(116, 212, 255, 0.15)", // $primary tint
        })
      }
      if (ds.dashed) base.borderDash = [6, 4]
      return base
    })
```

and replace the `plugins:` block of the returned config:

```js
        plugins: {
          legend: { labels: { color: TICK_COLOR, boxWidth: 14 } },
          tooltip: { mode: "index", intersect: false },
        },
```

with:

```js
        plugins: {
          legend: {
            labels: {
              color: TICK_COLOR, boxWidth: 14,
              filter: (item, chartData) => !chartData.datasets[item.datasetIndex].isBand,
            },
          },
          tooltip: { mode: "index", intersect: false, filter: (item) => !item.dataset.isBand },
        },
```

- [ ] **Step 4: Verify in the browser**

With `AUTO_LOGIN=1 bin/dev` running, open `/reports`, run "Cohort GPA by semester" with Program group = CP, Admission year = 2565.
Expected: line chart with a shaded band around the GPS average, dashed GPAX line, legend showing only "GPS avg" and "GPAX avg"; table below with Term ("2565/1"…), N, six GPS columns, six GPAX columns. Also confirm the existing course GPA-trend chart (a course show page) still renders unchanged.

- [ ] **Step 5: Commit**

```bash
hg add app/services/reports/cohort_gpa.rb
hg commit app/services/reports/cohort_gpa.rb app/services/reports/registry.rb app/javascript/controllers/chart_controller.js -m "Second grade report: staff want a cohort's per-semester GPA trajectory with
spread, not just averages - the +-2SD envelope shows whether the cohort is
tightening or spreading over time.

Add Reports::CohortGpa (GPS + GPAX aggregate columns per term, labels in
B.E.) and extend gpaTrendConfig with band datasets (role: band-upper/lower,
invisible lines + fill between, excluded from legend and tooltip) and a
dashed-line flag for the GPAX average."
```

---

### Task 7: LINE `GradeDistributionTool`

**Files:**
- Create: `app/services/line/tools/grade_distribution_tool.rb`
- Modify: `config/initializers/line_tools.rb`

**Interfaces:**
- Consumes: `GradeStats::CourseDistribution.call` (Task 1), `Line::ToolRegistry.register`.
- Produces: tool `"grade_distribution"`. `Line::Tools::GradeDistributionTool.call(arguments) -> String` (JSON). With semester: `{course_no, name_en, name_th, year_ce, semester, total, counts, gpa}`. Without: `{course_no, name_en, name_th, year_ce, semesters: [{semester, total, counts, gpa}]}`. Errors: `{error: "..."}`.

- [ ] **Step 1: Create `app/services/line/tools/grade_distribution_tool.rb`**

```ruby
# Grade distribution + course GPA for one course in one term (or all terms of
# a year). Aggregates across ALL curriculum revisions of the course_no.
class Line::Tools::GradeDistributionTool
  DEFINITION = {
    description: "Get the grade distribution (count of students per grade: A, B+, B, ...) and the " \
                 "course GPA (mean/SD over A-F grades) for a course in an academic year, optionally " \
                 "a specific semester. Counts combine all curriculum revisions of the course.",
    parameters: {
      type: "object",
      properties: {
        course_no: {
          type: "string",
          description: "Course number, e.g. '2110327'"
        },
        year: {
          type: "integer",
          description: "Academic year. Buddhist Era (e.g. 2568) or Christian Era (e.g. 2025) accepted; " \
                       "values below 2400 are treated as C.E."
        },
        semester: {
          type: "integer",
          description: "Semester: 1, 2, or 3 (summer). Omit to get every semester of the year."
        }
      },
      required: [ "course_no", "year" ]
    }
  }.freeze

  def self.call(arguments)
    course_no = arguments["course_no"].to_s.strip
    year = arguments["year"].to_i
    return { error: "course_no and year are required" }.to_json if course_no.blank? || year.zero?

    course = Course.where(course_no: course_no).order(revision_year_be: :desc).first
    return { error: "No course found with course_no #{course_no}" }.to_json unless course

    year_ce = year < 2400 ? year : year - 543
    semester = arguments["semester"].presence&.to_i

    base = { course_no: course_no, name_en: course.name, name_th: course.name_th, year_ce: year_ce }
    if semester
      dist = GradeStats::CourseDistribution.call(course_no: course_no, year_ce: year_ce, semester: semester)
      base.merge(dist.except(:course_no, :year_ce)).to_json
    else
      terms = GradeStats::CourseDistribution.call(course_no: course_no, year_ce: year_ce)
      base.merge(semesters: terms.map { |t| t.except(:course_no, :year_ce) }).to_json
    end
  end
end
```

- [ ] **Step 2: Register in `config/initializers/line_tools.rb`**

Add before the closing `end` of the `to_prepare` block:

```ruby
  Line::ToolRegistry.register(
    "grade_distribution",
    definition: Line::Tools::GradeDistributionTool::DEFINITION,
    handler: Line::Tools::GradeDistributionTool
  )
```

- [ ] **Step 3: Spot-check**

Run:
```bash
bin/rails runner 'puts Line::Tools::GradeDistributionTool.call({"course_no" => "2110327", "year" => 2025, "semester" => 2})'
bin/rails runner 'puts Line::Tools::GradeDistributionTool.call({"course_no" => "2110327", "year" => 2568, "semester" => 2})'
bin/rails runner 'puts Line::Tools::GradeDistributionTool.call({"course_no" => "2110327", "year" => 2567})'
```
Expected: first two print IDENTICAL JSON (era rule: 2025 C.E. ≡ 2568 B.E.) with counts + gpa; third prints a `semesters` array. If the LINE dev environment is up, also ask the bot "What is the grade distribution of 2110327 in semester 2/2568?" and check it answers with the counts.

- [ ] **Step 4: Commit**

```bash
hg add app/services/line/tools/grade_distribution_tool.rb
hg commit app/services/line/tools/grade_distribution_tool.rb config/initializers/line_tools.rb -m 'Staff want to ask the LINE bot questions like "what is the grade
distribution of 2110327 in semester 2/2568" instead of opening the web
reports.

Add the grade_distribution LLM tool on top of GradeStats::CourseDistribution.
Year accepts either era (< 2400 = C.E.); omitting semester returns every term
of the year in one call so the LLM does not need a retry round-trip.'
```

---

### Task 8: LINE `CohortGpaTool`

**Files:**
- Create: `app/services/line/tools/cohort_gpa_tool.rb`
- Modify: `config/initializers/line_tools.rb`

**Interfaces:**
- Consumes: `GradeStats::CohortGpa.call` (Task 3), `Line::ToolRegistry.register`.
- Produces: tool `"cohort_gpa"`. `call(arguments) -> String` (JSON): `{program, admission_year_be, terms: [{term: "2565/1", year_ce, semester, gps: AGG, gpax: AGG}]}`. Errors: `{error: "..."}`.

- [ ] **Step 1: Create `app/services/line/tools/cohort_gpa_tool.rb`**

```ruby
# Per-semester GPA statistics for one admission cohort (class year) of a
# program group. GPS = that term's GPA, GPAX = cumulative GPA through the term.
class Line::Tools::CohortGpaTool
  DEFINITION = {
    description: "Get per-semester GPA statistics for one admission cohort (class year) of a program. " \
                 "For each semester, returns GPS (that term's GPA) and GPAX (cumulative GPA) " \
                 "aggregated over the cohort: n, avg, sd, min, max, avg-2sd (minus2sd), avg+2sd (plus2sd). " \
                 "Term labels are Buddhist Era, e.g. '2565/1'.",
    parameters: {
      type: "object",
      properties: {
        program_code: {
          type: "string",
          description: "Program group code: CP, CEDT, CM, CS, SE, or CD"
        },
        admission_year: {
          type: "integer",
          description: "Admission year of the cohort. Buddhist Era (e.g. 2565) or Christian Era (e.g. 2022) " \
                       "accepted; values below 2400 are treated as C.E."
        }
      },
      required: [ "program_code", "admission_year" ]
    }
  }.freeze

  def self.call(arguments)
    code = arguments["program_code"].to_s.strip.upcase
    year = arguments["admission_year"].to_i
    return { error: "program_code and admission_year are required" }.to_json if code.blank? || year.zero?

    group = ProgramGroup.find_by(code: code)
    unless group
      valid = ProgramGroup.order(:code).pluck(:code).join(", ")
      return { error: "Unknown program code #{code}. Valid codes: #{valid}" }.to_json
    end

    # Students store admission year in B.E. — the opposite conversion from grades.
    admission_year_be = year < 2400 ? year + 543 : year
    data = GradeStats::CohortGpa.call(program_group: group, admission_year_be: admission_year_be)

    {
      program: group.code,
      admission_year_be: admission_year_be,
      terms: data[:terms].map do |t|
        { term: "#{t[:year_ce] + 543}/#{t[:semester]}",
          year_ce: t[:year_ce], semester: t[:semester],
          gps: t[:gps], gpax: t[:gpax] }
      end
    }.to_json
  end
end
```

- [ ] **Step 2: Register in `config/initializers/line_tools.rb`**

Add after the Task 7 registration, before the block's closing `end`:

```ruby
  Line::ToolRegistry.register(
    "cohort_gpa",
    definition: Line::Tools::CohortGpaTool::DEFINITION,
    handler: Line::Tools::CohortGpaTool
  )
```

- [ ] **Step 3: Spot-check**

Run:
```bash
bin/rails runner 'puts Line::Tools::CohortGpaTool.call({"program_code" => "cp", "admission_year" => 2565})'
bin/rails runner 'puts Line::Tools::CohortGpaTool.call({"program_code" => "CP", "admission_year" => 2022})'
bin/rails runner 'puts Line::Tools::CohortGpaTool.call({"program_code" => "ZZ", "admission_year" => 2565})'
```
Expected: first two print IDENTICAL JSON (case-insensitive code; 2022 C.E. ≡ 2565 B.E.); third prints the unknown-code error listing valid codes.

- [ ] **Step 4: Commit**

```bash
hg add app/services/line/tools/cohort_gpa_tool.rb
hg commit app/services/line/tools/cohort_gpa_tool.rb config/initializers/line_tools.rb -m 'Cohort performance questions ("how is the CP 2565 class doing?") should be
answerable in LINE chat, matching the new web report.

Add the cohort_gpa LLM tool on top of GradeStats::CohortGpa: per-term GPS and
GPAX aggregates with B.E. term labels. Admission year accepts either era
(< 2400 = C.E., converted by +543 - the opposite direction from grade years,
since students store admission_year_be).'
```

---

### Task 9: `GradeStats` service tests

**Files:**
- Create: `test/services/grade_stats/course_distribution_test.rb`
- Create: `test/services/grade_stats/semester_course_table_test.rb`
- Create: `test/services/grade_stats/cohort_gpa_test.rb`

**Interfaces:**
- Consumes: Tasks 1–3 public APIs; fixtures `programs(:cp_bachelor)`, `program_groups(:cp_group)` (referenced, never mutated).
- Produces: green tests. **Isolation rules:** course_nos start with `99…`; cohort admission years are 2599/2600 (fixture students use 2565–2567 and would pollute a 2565 cohort).

- [ ] **Step 1: Create `test/services/grade_stats/course_distribution_test.rb`**

```ruby
require "test_helper"

class GradeStats::CourseDistributionTest < ActiveSupport::TestCase
  # Isolated records, not fixtures: the LINE lookup-tool tests assert exact
  # fixture counts, so stats data lives only inside this test's transaction.
  setup do
    @old = Course.create!(course_no: "9910327", name: "Algo (old rev)", revision_year_be: 2560, credits: 3)
    @new = Course.create!(course_no: "9910327", name: "Algo (new rev)", revision_year_be: 2566, credits: 3)
    @s1, @s2, @s3, @s4 = (1..4).map { |i| make_student("99000001#{i.to_s.rjust(2, '0')}") }
    grade(@s1, @old, "A", 4.0)
    grade(@s2, @new, "A", 4.0)
    grade(@s3, @new, "B+", 3.5)
    grade(@s4, @new, "S", nil)   # counted in the distribution, excluded from GPA
  end

  test "combines all revisions of a course_no, counts ordered by GRADES" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 2)

    assert_equal({ "A" => 2, "B+" => 1, "S" => 1 }, r[:counts])
    assert_equal %w[A B+ S], r[:counts].keys
    assert_equal 4, r[:total]
  end

  test "GPA covers weighted grades only, sample SD, 2 decimals" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 2)

    assert_equal 3, r[:gpa][:n]                 # the S row is excluded
    assert_in_delta 3.83, r[:gpa][:mean], 0.001 # (4 + 4 + 3.5) / 3
    assert_in_delta 0.29, r[:gpa][:sd], 0.001   # sample SD of [4, 4, 3.5]
  end

  test "nil semester returns one result per term of the year, in order" do
    grade(@s1, @new, "B", 3.0, semester: 1)

    results = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025)

    assert_equal [ 1, 2 ], results.map { |r| r[:semester] }
    assert_equal({ "B" => 1 }, results.first[:counts])
  end

  test "term with no grades returns an empty distribution" do
    r = GradeStats::CourseDistribution.call(course_no: "9910327", year_ce: 2025, semester: 3)

    assert_equal 0, r[:total]
    assert_empty r[:counts]
    assert_equal({ n: 0, mean: nil, sd: nil }, r[:gpa])
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, letter, weight, semester: 2)
    Grade.create!(student: student, course: course, year_ce: 2025, semester: semester,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
```

- [ ] **Step 2: Create `test/services/grade_stats/semester_course_table_test.rb`**

```ruby
require "test_helper"

class GradeStats::SemesterCourseTableTest < ActiveSupport::TestCase
  # Isolated records (see course_distribution_test.rb for why). year_ce 2030
  # avoids the fixture grades (2022/2024) attached to cp_bachelor's courses.
  setup do
    @in1a = Course.create!(course_no: "9920001", name: "In (old rev)", revision_year_be: 2560, credits: 3)
    @in1b = Course.create!(course_no: "9920001", name: "In (new rev)", revision_year_be: 2566, credits: 3)
    @in2  = Course.create!(course_no: "9920002", name: "Also in", revision_year_be: 2566, credits: 3)
    @out  = Course.create!(course_no: "9920003", name: "Not in program", revision_year_be: 2566, credits: 3)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in1a)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in1b)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @in2)

    @s1, @s2, @s3 = (1..3).map { |i| make_student("99000002#{i.to_s.rjust(2, '0')}") }
    grade(@s1, @in1a, "A", 4.0)   # old revision …
    grade(@s2, @in1b, "F", 0.0)   # … and new revision must merge into one row
    grade(@s3, @in2,  "B+", 3.5)
    grade(@s1, @out,  "A", 4.0)   # outside the program — must not appear
  end

  test "one row per course_no in the program group, revisions merged" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    assert_equal %w[9920001 9920002], r[:rows].map { |row| row[:course_no] }
    merged = r[:rows].first
    assert_equal({ "A" => 1, "F" => 1 }, merged[:counts])
    assert_equal 2, merged[:total]
    assert_equal "In (new rev)", merged[:name]  # latest revision's name
  end

  test "grade_columns is the GRADES-ordered union of grades present" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    assert_equal %w[A B+ F], r[:grade_columns]
  end

  test "per-course GPA uses sample SD and rounds to 2 decimals" do
    r = GradeStats::SemesterCourseTable.call(program_group: program_groups(:cp_group),
                                             year_ce: 2030, semester: 1)

    merged = r[:rows].first
    assert_equal 2, merged[:gpa][:n]
    assert_in_delta 2.0, merged[:gpa][:mean], 0.001   # (4 + 0) / 2
    assert_in_delta 2.83, merged[:gpa][:sd], 0.001    # sample SD of [4, 0]
    single = r[:rows].second
    assert_nil single[:gpa][:sd]                      # STDDEV_SAMP is NULL for n=1
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, letter, weight)
    Grade.create!(student: student, course: course, year_ce: 2030, semester: 1,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
```

- [ ] **Step 3: Create `test/services/grade_stats/cohort_gpa_test.rb`**

```ruby
require "test_helper"

class GradeStats::CohortGpaTest < ActiveSupport::TestCase
  # Isolated records (see course_distribution_test.rb for why). Cohort year
  # 2599 avoids fixture students (2565-2567 in cp_group).
  setup do
    @c3 = Course.create!(course_no: "9930001", name: "Three credits", revision_year_be: 2566, credits: 3)
    @c2 = Course.create!(course_no: "9930002", name: "Two credits", revision_year_be: 2566, credits: 2)
    @a = make_student("9900000301")
    @b = make_student("9900000302")
    @other = make_student("9900000303", admission_year_be: 2600)  # different cohort

    # Term 2022/1 — a: A(3cr) + B(2cr) → GPS 3.6; b: C+(3cr) → GPS 2.5
    grade(@a, @c3, 2022, 1, "A", 4.0)
    grade(@a, @c2, 2022, 1, "B", 3.0)
    grade(@b, @c3, 2022, 1, "C+", 2.5)
    # Term 2022/2 — a: D(2cr) → GPS 1.0; b: S only → no GPS, GPAX unchanged
    grade(@a, @c2, 2022, 2, "D", 1.0)
    grade(@b, @c2, 2022, 2, "S", nil)
    # Different cohort — must not appear anywhere
    grade(@other, @c3, 2022, 1, "F", 0.0)
  end

  test "GPS aggregates per term over the cohort only" do
    t1 = call.first

    assert_equal [ 2022, 1 ], [ t1[:year_ce], t1[:semester] ]
    assert_equal 2, t1[:gps][:n]
    assert_in_delta 3.05, t1[:gps][:avg], 0.001   # (3.6 + 2.5) / 2 — the F outsider excluded
    assert_in_delta 0.78, t1[:gps][:sd], 0.001    # sample SD of [3.6, 2.5]
    assert_in_delta 2.5,  t1[:gps][:min], 0.001
    assert_in_delta 3.6,  t1[:gps][:max], 0.001
    assert_in_delta 3.05 - 2 * 0.78, t1[:gps][:minus2sd], 0.01
    assert_in_delta 3.05 + 2 * 0.78, t1[:gps][:plus2sd], 0.01
  end

  test "GPAX is cumulative; only-S/U student keeps GPAX but drops from GPS" do
    t2 = call.second

    assert_equal [ 2022, 2 ], [ t2[:year_ce], t2[:semester] ]
    assert_equal 1, t2[:gps][:n]                  # only a has a weighted grade
    assert_in_delta 1.0, t2[:gps][:avg], 0.001
    assert_equal 2, t2[:gpax][:n]                 # b's history still counts
    # a: (12 + 6 + 2) / 7 = 2.857…; b: unchanged 2.5 → avg 2.68
    assert_in_delta 2.68, t2[:gpax][:avg], 0.001
  end

  test "terms are chronological and empty cohorts return no terms" do
    assert_equal [ [ 2022, 1 ], [ 2022, 2 ] ], call.map { |t| [ t[:year_ce], t[:semester] ] }

    empty = GradeStats::CohortGpa.call(program_group: program_groups(:cp_group),
                                       admission_year_be: 2601)
    assert_empty empty[:terms]
  end

  private

  def call
    GradeStats::CohortGpa.call(program_group: program_groups(:cp_group),
                               admission_year_be: 2599)[:terms]
  end

  def make_student(id, admission_year_be: 2599)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: admission_year_be, status: "active",
                    program: programs(:cp_bachelor))
  end

  def grade(student, course, year, semester, letter, weight)
    Grade.create!(student: student, course: course, year_ce: year, semester: semester,
                  grade: letter, grade_weight: weight, source: "imported")
  end
end
```

- [ ] **Step 4: Run the new tests**

Run: `bin/rails test test/services/grade_stats -v`
Expected: 11 tests, 0 failures. If an assertion value disagrees, re-derive by hand before touching the service — the expected numbers above are hand-computed.

- [ ] **Step 5: Commit**

```bash
hg add test/services/grade_stats
hg commit test/services/grade_stats -m "The GradeStats services carry all the math for the new grade reports, and
both surfaces (web + LINE) trust their numbers blindly - hand-computed
expected values are the only guard against silent statistical bugs.

Cover: revision merging by course_no, GRADES-ordered counts, S/U excluded
from GPA but present in distributions, program-group scoping, latest-revision
names, sample SD (incl. NULL for n=1), GPS vs GPAX semantics (gap-semester
student keeps GPAX), chronological terms, empty inputs."
```

---

### Task 10: Report tests

**Files:**
- Create: `test/services/reports/semester_grade_distribution_test.rb`
- Create: `test/services/reports/cohort_gpa_test.rb`

**Interfaces:**
- Consumes: Tasks 5–6 report classes; same isolation rules as Task 9.
- Produces: green tests proving the B.E. contract, dynamic columns, chart payloads, and registry presence.

- [ ] **Step 1: Create `test/services/reports/semester_grade_distribution_test.rb`**

```ruby
require "test_helper"

class Reports::SemesterGradeDistributionTest < ActiveSupport::TestCase
  # Isolated records (LINE lookup-tool tests assert exact fixture counts).
  # year_ce 2030 = B.E. 2573 avoids fixture grades.
  setup do
    @course = Course.create!(course_no: "9940001", name: "Report Course", revision_year_be: 2566, credits: 3)
    ProgramCourse.create!(program: programs(:cp_bachelor), course: @course)
    s1 = make_student("9900000401")
    s2 = make_student("9900000402")
    Grade.create!(student: s1, course: @course, year_ce: 2030, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: s2, course: @course, year_ce: 2030, semester: 1,
                  grade: "B+", grade_weight: 3.5, source: "imported")
  end

  test "builds dynamic grade columns and a chart from the term's data (B.E. input)" do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "CP", "year" => "2573", "term" => "1"
    ).run

    assert_equal [ "Course No", "Name", "N", "A", "B+", "GPA", "SD" ],
                 result.columns.map { |c| c[:label] }
    row = result.rows.find { |r| r[:course_no] == "9940001" }
    assert_equal 1, row[:g_a]
    assert_equal 1, row[:g_bp]
    assert_equal 2, row[:total]
    assert_in_delta 3.75, row[:gpa], 0.001

    assert_equal "horizontal-stacked-bar", result.chart[:type]
    assert_equal "grade", result.chart[:data][:colorBy]
    assert_includes result.chart[:data][:labels], "9940001"
  end

  test "treats the year param as Buddhist Era, not C.E." do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "CP", "year" => "2030", "term" => "1"
    ).run
    assert_empty result.rows
  end

  test "unknown program group returns an empty result, and no chart when empty" do
    result = Reports::SemesterGradeDistribution.new(
      "program_group" => "ZZ", "year" => "2573", "term" => "1"
    ).run
    assert result.empty?
    assert_nil result.chart
  end

  test "is registered" do
    assert_equal Reports::SemesterGradeDistribution,
                 Reports::Registry.find("semester_grade_distribution")
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end
end
```

- [ ] **Step 2: Create `test/services/reports/cohort_gpa_test.rb`**

```ruby
require "test_helper"

class Reports::CohortGpaTest < ActiveSupport::TestCase
  # Isolated records; cohort year 2599 avoids fixture students (2565-2567).
  setup do
    course = Course.create!(course_no: "9950001", name: "Cohort Course", revision_year_be: 2566, credits: 3)
    s1 = make_student("9900000501")
    s2 = make_student("9900000502")
    Grade.create!(student: s1, course: course, year_ce: 2022, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: s2, course: course, year_ce: 2022, semester: 1,
                  grade: "B", grade_weight: 3.0, source: "imported")
  end

  test "one row per term with GPS and GPAX stats, term labels in B.E." do
    result = Reports::CohortGpa.new(
      "program_group" => "CP", "admission_year" => "2599"
    ).run

    labels = result.columns.map { |c| c[:label] }
    assert_equal "Term", labels.first
    assert_includes labels, "GPS avg"
    assert_includes labels, "GPAX +2SD"
    assert_equal 14, labels.size

    row = result.rows.first
    assert_equal "2565/1", row[:term]   # year_ce 2022 + 543
    assert_equal 2, row[:n]
    assert_in_delta 3.5, row[:gps_avg], 0.001
    assert_in_delta 3.5, row[:gpax_avg], 0.001
  end

  test "chart has band-upper/band-lower/avg/dashed-GPAX datasets" do
    result = Reports::CohortGpa.new(
      "program_group" => "CP", "admission_year" => "2599"
    ).run

    assert_equal "gpa-trend", result.chart[:type]
    datasets = result.chart[:data][:datasets]
    assert_equal [ "band-upper", "band-lower", nil, nil ], datasets.map { |d| d[:role] }
    assert datasets.last[:dashed]
    assert_equal [ "2565/1" ], result.chart[:data][:labels]
  end

  test "unknown program group returns an empty result" do
    result = Reports::CohortGpa.new(
      "program_group" => "ZZ", "admission_year" => "2599"
    ).run
    assert result.empty?
    assert_nil result.chart
  end

  test "is registered" do
    assert_equal Reports::CohortGpa, Reports::Registry.find("cohort_gpa")
  end

  private

  def make_student(id)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: 2599, status: "active",
                    program: programs(:cp_bachelor))
  end
end
```

- [ ] **Step 3: Run the report test suite**

Run: `bin/rails test test/services/reports -v`
Expected: all green — the 8 new tests plus the existing report tests (registry test uses `assert_includes`, so the two new registry entries don't break it).

- [ ] **Step 4: Commit**

```bash
hg add test/services/reports/semester_grade_distribution_test.rb test/services/reports/cohort_gpa_test.rb
hg commit test/services/reports/semester_grade_distribution_test.rb test/services/reports/cohort_gpa_test.rb -m "The new grade reports carry contracts the framework cannot check: the year
param is B.E. (a past regression class - see failing_students_test), grade
columns are dynamic, and chart payloads must match what chart_controller
expects (colorBy, band roles, dashed flag).

Cover both report classes: column construction, B.E.-vs-C.E. year handling,
unknown program group, chart payload shape, registry presence."
```

---

### Task 11: LINE tool tests

**Files:**
- Create: `test/services/line/tools/grade_distribution_tool_test.rb`
- Create: `test/services/line/tools/cohort_gpa_tool_test.rb`

**Interfaces:**
- Consumes: Tasks 7–8 tools; same isolation rules as Task 9.
- Produces: green tests proving JSON shape and the era rule in both directions.

- [ ] **Step 1: Create `test/services/line/tools/grade_distribution_tool_test.rb`**

```ruby
require "test_helper"

class Line::Tools::GradeDistributionToolTest < ActiveSupport::TestCase
  # Isolated records (the sibling lookup-tool tests assert exact fixture counts).
  setup do
    @course = Course.create!(course_no: "9960001", name: "Tool Course", name_th: "วิชาทดสอบ",
                             revision_year_be: 2566, credits: 3)
    student = Student.create!(student_id: "9900000601", first_name: "T", last_name: "S",
                              first_name_th: "ท", last_name_th: "ส",
                              admission_year_be: 2599, status: "active",
                              program: programs(:cp_bachelor))
    Grade.create!(student: student, course: @course, year_ce: 2025, semester: 2,
                  grade: "A", grade_weight: 4.0, source: "imported")
  end

  test "returns distribution and GPA; C.E. and B.E. years are equivalent" do
    ce = JSON.parse(Line::Tools::GradeDistributionTool.call(
      "course_no" => "9960001", "year" => 2025, "semester" => 2))
    be = JSON.parse(Line::Tools::GradeDistributionTool.call(
      "course_no" => "9960001", "year" => 2568, "semester" => 2))

    assert_equal ce, be
    assert_equal({ "A" => 1 }, ce["counts"])
    assert_equal 1, ce["total"]
    assert_equal "Tool Course", ce["name_en"]
    assert_equal 2025, ce["year_ce"]
    assert_in_delta 4.0, ce["gpa"]["mean"], 0.001
  end

  test "omitting semester returns every term of the year" do
    result = JSON.parse(Line::Tools::GradeDistributionTool.call(
      "course_no" => "9960001", "year" => 2568))

    assert_equal 1, result["semesters"].size
    assert_equal 2, result["semesters"].first["semester"]
  end

  test "unknown course and missing params return errors" do
    assert_includes Line::Tools::GradeDistributionTool.call(
      "course_no" => "0000000", "year" => 2568), "error"
    assert_includes Line::Tools::GradeDistributionTool.call(
      "course_no" => "9960001"), "error"
  end
end
```

- [ ] **Step 2: Create `test/services/line/tools/cohort_gpa_tool_test.rb`**

```ruby
require "test_helper"

class Line::Tools::CohortGpaToolTest < ActiveSupport::TestCase
  # Isolated records; cohort year 2599 (B.E.) = 2056 (C.E.) avoids fixtures.
  setup do
    course = Course.create!(course_no: "9970001", name: "Cohort Tool Course",
                            revision_year_be: 2566, credits: 3)
    student = Student.create!(student_id: "9900000701", first_name: "T", last_name: "S",
                              first_name_th: "ท", last_name_th: "ส",
                              admission_year_be: 2599, status: "active",
                              program: programs(:cp_bachelor))
    Grade.create!(student: student, course: course, year_ce: 2022, semester: 1,
                  grade: "B+", grade_weight: 3.5, source: "imported")
  end

  test "returns per-term GPS/GPAX; B.E. and C.E. admission years are equivalent" do
    be = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "CP", "admission_year" => 2599))
    ce = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "cp", "admission_year" => 2056))

    assert_equal be, ce                       # era rule + case-insensitive code
    assert_equal "CP", be["program"]
    assert_equal 2599, be["admission_year_be"]
    term = be["terms"].first
    assert_equal "2565/1", term["term"]
    assert_in_delta 3.5, term["gps"]["avg"], 0.001
    assert_in_delta 3.5, term["gpax"]["avg"], 0.001
  end

  test "unknown program code returns an error listing valid codes" do
    result = JSON.parse(Line::Tools::CohortGpaTool.call(
      "program_code" => "ZZ", "admission_year" => 2599))

    assert_match(/Unknown program code ZZ/, result["error"])
    assert_match(/CP/, result["error"])
  end
end
```

- [ ] **Step 3: Run the LINE tool test suite**

Run: `bin/rails test test/services/line/tools -v`
Expected: all green — the 5 new tests plus the existing lookup-tool tests (proving the isolated records didn't disturb their exact-count assertions).

- [ ] **Step 4: Commit**

```bash
hg add test/services/line/tools/grade_distribution_tool_test.rb test/services/line/tools/cohort_gpa_tool_test.rb
hg commit test/services/line/tools/grade_distribution_tool_test.rb test/services/line/tools/cohort_gpa_tool_test.rb -m "The LINE grade tools apply era conversion in OPPOSITE directions (grade
years convert to C.E., admission years to B.E.) - exactly the kind of
asymmetry that silently breaks, and the LLM cannot detect wrong numbers.

Cover both tools: era equivalence in both directions, JSON shape the LLM
consumes, all-terms mode, and error paths (unknown course/program, missing
params)."
```

---

### Task 12: System tests

**Files:**
- Create: `test/system/grade_reports_test.rb`

**Interfaces:**
- Consumes: everything; fixture data (`users(:admin)` signs in with `password123`; fixture grades: `2110101` has an A and `2103106` a B in `year_ce` 2024/1 for CP students admitted B.E. 2567).
- Produces: a green happy-path system test per report.

- [ ] **Step 1: Create `test/system/grade_reports_test.rb`**

```ruby
require "application_system_test_case"

class GradeReportsTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "semester grade distribution: form -> chart + table" do
    sign_in users(:admin)
    visit report_path("semester_grade_distribution")

    select "CP", from: "program_group"
    fill_in "year", with: "2567"          # B.E. of the 2024 fixture grades
    select "First", from: "term"
    click_on "Run report"

    assert_text "2110101"                 # intro_computing row (grade A fixture)
    assert_text "GPA"
    assert_selector "canvas"              # the horizontal stacked-bar chart
  end

  test "cohort GPA: form -> chart + table with B.E. term labels" do
    sign_in users(:admin)
    visit report_path("cohort_gpa")

    select "CP", from: "program_group"
    fill_in "admission_year", with: "2567" # active_student's cohort
    click_on "Run report"

    assert_text "2567/1"                  # year_ce 2024 + 543
    assert_text "GPS avg"
    assert_selector "canvas"              # the GPA trend chart
  end

  test "both reports appear on the reports index" do
    sign_in users(:admin)
    visit reports_path

    assert_text "Grade distribution by course"
    assert_text "Cohort GPA by semester"
  end
end
```

- [ ] **Step 2: Run the system tests**

Run: `bin/rails test:system TEST=test/system/grade_reports_test.rb`
Expected: 3 tests, 0 failures (headless Firefox). If `fill_in "year"` can't find the field, the label text is the humanized param name — try `fill_in "Year", with: "2567"`.

- [ ] **Step 3: Run the full test suite**

Run: `bin/rails test 2>&1 | tail -3`
Expected: everything green.

- [ ] **Step 4: Commit**

```bash
hg add test/system/grade_reports_test.rb
hg commit test/system/grade_reports_test.rb -m "The grade reports span the full stack (param form -> report class ->
GradeStats -> chart partial -> Stimulus chart), and only a browser test
proves the pieces are actually wired together.

Add happy-path system tests: run each report from its form against fixture
grades, assert the result table and chart canvas render, and both reports
appear on the reports index."
```

---

## Verification checklist (after all tasks)

- [ ] `bin/rails test && bin/rails test:system` — all green.
- [ ] Web: `/reports` shows both new reports; each runs with CP + real data (year 2568/2567) and renders chart + table + CSV.
- [ ] LINE (dev): "What is the grade distribution of 2110327 in semester 2/2568?" and "How is the CP 2565 cohort doing?" both get numeric answers.
- [ ] Spot-check one course's distribution against the course show page's existing per-term chart — the numbers must agree.
