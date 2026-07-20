# Grade Distribution CSV Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CSV download to the grade-distribution report at `/grades/distribution`, mirroring the reports-hub export convention.

**Architecture:** `GradesController#distribution` gains a `respond_to` block whose `format.csv` branch sends a file built by a new `Exporters::GradeDistributionExporter` (same shape as `Exporters::ReportExporter`). The view gets the same "Results" title row + Export CSV link that `reports/_result_table.html.haml` uses. No JS changes.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, HAML, Minitest + fixtures. Spec: `docs/superpowers/specs/2026-07-20-grade-distribution-csv-export-design.md`.

## Global Constraints

- **Version control is Mercurial (hg), not git.** Commit with `hg add <files>` (new files) + `hg commit <explicit files> -m "..."` — always name the files; the repo often has unrelated dirty changes.
- **Commit messages lead with WHY, not what** — first paragraph is motivation, second is the change.
- **Tests are written only after user confirmation** (project convention: "after implementing a feature, ask whether to write tests"). Task 4 is gated on that; do not start it unprompted.
- **Intranet-only app**: no CDN links or external assets (this plan adds none).
- The export reflects the **applied** form filters only; DataTables search-box text is deliberately not included (approved trade-off).

---

### Task 1: `Exporters::GradeDistributionExporter`

**Files:**
- Create: `app/services/exporters/grade_distribution_exporter.rb`

**Interfaces:**
- Consumes: `GradesController::LETTER_GRADES` (`%w[A B+ B C+ C D+ D F]`, already referenced from the view layer) and the `@rows` hash shape built by `GradesController#distribution_row`: `{ course_no:, title:, term_key:, term:, buckets:, other:, n:, gpa:, pass_rate: }` where `buckets` maps `"A".."F"` and `"W"` to Integer counts, `gpa`/`pass_rate` are Numeric or nil.
- Produces: `Exporters::GradeDistributionExporter.new(rows:, split:)` with `#to_csv` → String and `#filename` → `"grade_distribution.csv"`. Task 2 calls exactly these.

- [ ] **Step 1: Write the exporter**

Create `app/services/exporters/grade_distribution_exporter.rb`:

```ruby
require "csv"

module Exporters
  # Turns the grade-distribution report's rows (GradesController#distribution)
  # into a CSV download. Column order mirrors the on-screen table; GPA and
  # pass-rate are bare numbers (blank when nil) so spreadsheets can sort them.
  class GradeDistributionExporter
    def initialize(rows:, split:)
      @rows = rows
      @split = split
    end

    def to_csv
      CSV.generate do |csv|
        csv << header
        @rows.each { |row| csv << row_values(row) }
      end
    end

    def filename
      "grade_distribution.csv"
    end

    private

    def header
      cols = %w[Course Title]
      cols << "Term" if @split
      cols + GradesController::LETTER_GRADES + ["W", "Other", "N", "GPA", "% ≥ C"]
    end

    def row_values(row)
      vals = [row[:course_no], row[:title]]
      vals << row[:term] if @split
      vals += (GradesController::LETTER_GRADES + %w[W]).map { |g| row[:buckets][g] }
      vals + [row[:other], row[:n], row[:gpa], row[:pass_rate]]
    end
  end
end
```

- [ ] **Step 2: Smoke-check via runner**

Run:

```bash
bin/rails runner 'rows = [{course_no: "2110101", title: "Intro", term: "2024/1", buckets: {"A"=>1,"B+"=>0,"B"=>0,"C+"=>0,"C"=>0,"D+"=>0,"D"=>0,"F"=>0,"W"=>0}, other: 0, n: 1, gpa: 4.0, pass_rate: 100}, {course_no: "2110499", title: "SP", term: "2024/2", buckets: {"A"=>0,"B+"=>1,"B"=>0,"C+"=>0,"C"=>0,"D+"=>0,"D"=>0,"F"=>0,"W"=>0}, other: 0, n: 1, gpa: nil, pass_rate: nil}]; puts Exporters::GradeDistributionExporter.new(rows: rows, split: true).to_csv'
```

Expected output (note the trailing empty cells for nil GPA/pass-rate on the second row):

```
Course,Title,Term,A,B+,B,C+,C,D+,D,F,W,Other,N,GPA,% ≥ C
2110101,Intro,2024/1,1,0,0,0,0,0,0,0,0,0,1,4.0,100
2110499,SP,2024/2,0,1,0,0,0,0,0,0,0,0,1,,
```

- [ ] **Step 3: Commit**

```bash
hg add app/services/exporters/grade_distribution_exporter.rb
hg commit app/services/exporters/grade_distribution_exporter.rb -m "Add exporter for the grade-distribution report

The distribution report is the one grades view with no download path — getting
the numbers into a spreadsheet means copy-pasting the table. This exporter turns
the report's row hashes into CSV, following ReportExporter's to_csv/filename
shape so the controller wiring (next commit) matches the reports hub.

Columns mirror the on-screen table (Term only when split by semester); GPA and
pass-rate are bare numbers, blank when nil, so spreadsheets sort them cleanly."
```

---

### Task 2: `format.csv` on the distribution action

**Files:**
- Modify: `app/controllers/grades_controller.rb:27-45` (the `distribution` action)

**Interfaces:**
- Consumes: `Exporters::GradeDistributionExporter.new(rows:, split:)` / `#to_csv` / `#filename` from Task 1.
- Produces: `GET /grades/distribution.csv` honoring the same query params as the HTML report (`prefix`, `program_code`, `start_year`, `end_year`, `split`). Task 3's link relies on this route + format.

- [ ] **Step 1: Wrap the action's tail in `respond_to`**

In `app/controllers/grades_controller.rb`, replace the last two lines of `distribution`:

```ruby
    build_distribution_rows(counts)
    build_gpa_trend(counts)
  end
```

with:

```ruby
    build_distribution_rows(counts)

    respond_to do |format|
      format.html { build_gpa_trend(counts) }
      format.csv do
        exporter = Exporters::GradeDistributionExporter.new(rows: @rows, split: @split)
        send_data exporter.to_csv, filename: exporter.filename,
                  type: "text/csv", disposition: "attachment"
      end
    end
  end
```

`build_gpa_trend` moves inside `format.html` — the chart data is wasted work for a download (per spec). Everything above (filter parsing, `@rows`) is shared.

- [ ] **Step 2: Verify the CSV endpoint**

The route (`get :distribution` on the `grades` collection) already accepts `.csv` via the format segment. Auth requires a session, so verify with a throwaway auto-login server on a spare port:

```bash
AUTO_LOGIN=1 bin/rails server -p 3001 -d
curl -s "http://localhost:3001/grades/distribution.csv?prefix=2110&split=1" | head -3
kill "$(cat tmp/pids/server.pid)"
```

Expected: first line `Course,Title,Term,A,B+,B,C+,C,D+,D,F,W,Other,N,GPA,% ≥ C`, followed by data rows (development DB contents). Also confirm the HTML page still renders: `curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3001/grades/distribution"` → `200` (run before killing the server).

- [ ] **Step 3: Commit**

```bash
hg commit app/controllers/grades_controller.rb -m "Serve the grade-distribution report as CSV

Lecturers want the distribution numbers in a spreadsheet; until now the only way
was copy-pasting the rendered table. Reuse the reports-hub convention: the same
action answers format.csv with the same applied filters, so the download always
matches what the table shows.

distribution now wraps its tail in respond_to — build_gpa_trend moves into the
html branch (chart data is wasted work for a download), and the csv branch
send_datas GradeDistributionExporter's output."
```

---

### Task 3: Export button on the report page

**Files:**
- Modify: `app/views/grades/distribution.html.haml:45-48` (top of the table card)

**Interfaces:**
- Consumes: `GET /grades/distribution.csv` from Task 2; `request.query_parameters` carries the applied filters into the link (same pattern as `reports/_result_table.html.haml:17`).
- Produces: user-facing Export CSV button. Nothing downstream consumes this.

- [ ] **Step 1: Add the title row**

In `app/views/grades/distribution.html.haml`, inside the table card, replace:

```haml
  .card{"data-controller" => "datatable", "data-datatable-disable-last-column-value" => "false", "data-datatable-page-length-value" => "50"}
    .card-body.p-3
      .table-responsive
```

with:

```haml
  .card{"data-controller" => "datatable", "data-datatable-disable-last-column-value" => "false", "data-datatable-page-length-value" => "50"}
    .card-body.p-3
      .d-flex.justify-content-between.align-items-center.mb-3
        %h6.card-title.mb-0 Results
        = link_to distribution_grades_path(request.query_parameters.merge(format: :csv)), class: "btn btn-outline-secondary btn-sm" do
          %span.material-symbols{style: "font-size: 16px; vertical-align: middle;"} download
          Export CSV
      .table-responsive
```

Indentation: the new `.d-flex` row sits at the same depth as `.table-responsive` (6 spaces). The card is inside the `- if @rows.present?` branch, so no button renders when there is nothing to export.

- [ ] **Step 2: Verify in the browser**

Reload `http://localhost:3000/grades/distribution`. Expected: a "Results" title row with an Export CSV button (download icon, outline-secondary, same look as the reports hub). Change a filter (e.g. uncheck "Split by semester", click View), then click Export CSV — the downloaded file must reflect the change (no Term column).

- [ ] **Step 3: Commit**

```bash
hg commit app/views/grades/distribution.html.haml -m "Add Export CSV button to the grade-distribution report

The CSV endpoint (previous commit) needs a door on the page. Reuse the reports
hub's card title row verbatim — Results heading left, Export CSV button right —
so the two report surfaces look and behave identically. The link carries
request.query_parameters, so the download always matches the applied filters."
```

---

### Task 4: Tests — GATED: ask the user first

**Do not start this task until the user has confirmed.** Per project convention, ask: "Feature done — want the tests now? Planned: exporter unit test (column order, split/unsplit, nil-blank, filename) + two controller CSV integration tests." Adjust scope to their answer.

**Files:**
- Create: `test/services/exporters/grade_distribution_exporter_test.rb`
- Modify: `test/controllers/grades_controller_test.rb` (append two tests before the final `end`)

**Interfaces:**
- Consumes: Task 1's exporter API; Task 2's CSV endpoint; fixtures `test/fixtures/grades.yml` (2110101 gets an A in 2022/1 and 2024/1; 2110499 gets a B+ in 2024/2; 2103106 is the only non-2110 graded course) and `test/fixtures/courses.yml` (2110101 = "Introduction to Computing").
- Produces: regression coverage; nothing downstream.

- [ ] **Step 1: Write the exporter unit test**

Create `test/services/exporters/grade_distribution_exporter_test.rb`:

```ruby
require "test_helper"

class Exporters::GradeDistributionExporterTest < ActiveSupport::TestCase
  def sample_row(overrides = {})
    {
      course_no: "2110101",
      title: "Introduction to Computing",
      term_key: [2024, 1],
      term: "2024/1",
      buckets: { "A" => 5, "B+" => 2, "B" => 1, "C+" => 0, "C" => 3,
                 "D+" => 0, "D" => 0, "F" => 1, "W" => 2 },
      other: 1,
      n: 15,
      gpa: 3.12,
      pass_rate: 92
    }.merge(overrides)
  end

  test "split export mirrors the table's column order" do
    csv = CSV.parse(Exporters::GradeDistributionExporter.new(rows: [sample_row], split: true).to_csv)
    assert_equal ["Course", "Title", "Term", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    assert_equal ["2110101", "Introduction to Computing", "2024/1",
                  "5", "2", "1", "0", "3", "0", "0", "1", "2", "1", "15", "3.12", "92"], csv[1]
  end

  test "unsplit export omits the Term column" do
    exporter = Exporters::GradeDistributionExporter.new(
      rows: [sample_row(term: nil, term_key: nil)], split: false
    )
    csv = CSV.parse(exporter.to_csv)
    assert_equal ["Course", "Title", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    assert_equal "5", csv[1][2], "A-count should directly follow Title when unsplit"
  end

  test "nil GPA and pass rate export as blank cells, not em-dashes" do
    exporter = Exporters::GradeDistributionExporter.new(
      rows: [sample_row(gpa: nil, pass_rate: nil)], split: true
    )
    csv = CSV.parse(exporter.to_csv)
    assert_nil csv[1][-2]
    assert_nil csv[1][-1]
  end

  test "filename is the static report name" do
    assert_equal "grade_distribution.csv",
                 Exporters::GradeDistributionExporter.new(rows: [], split: true).filename
  end
end
```

- [ ] **Step 2: Run the exporter test**

Run: `bin/rails test test/services/exporters/grade_distribution_exporter_test.rb`
Expected: `4 runs, 9 assertions, 0 failures, 0 errors`

- [ ] **Step 3: Write the controller CSV tests**

Append inside `test/controllers/grades_controller_test.rb` (before the final `end`; the existing `setup` block already logs in as `users(:viewer)`):

```ruby
  test "distribution CSV export returns the full filtered result set" do
    get distribution_grades_path(format: :csv), params: { prefix: "2110", split: "1" }
    assert_response :success
    assert_equal "text/csv", response.media_type
    csv = CSV.parse(response.body)
    assert_equal ["Course", "Title", "Term", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    # Fixtures with a 2110 prefix: 2110101 gets an A in 2022/1 and 2024/1,
    # 2110499 a B+ in 2024/2 — three split rows, sorted by course_no then term.
    assert_equal 4, csv.size
    assert_equal ["2110101", "Introduction to Computing", "2022/1",
                  "1", "0", "0", "0", "0", "0", "0", "0", "0", "0", "1", "4.0", "100"], csv[1]
    refute_match "2103106", response.body, "non-2110 course must be filtered out"
  end

  test "distribution CSV without split aggregates terms and omits the Term column" do
    get distribution_grades_path(format: :csv), params: { prefix: "2110", split: "0" }
    assert_response :success
    csv = CSV.parse(response.body)
    assert_equal "A", csv[0][2], "A-count should directly follow Title when unsplit"
    assert_equal ["2110101", "Introduction to Computing",
                  "2", "0", "0", "0", "0", "0", "0", "0", "0", "0", "2", "4.0", "100"], csv[1]
  end
```

- [ ] **Step 4: Run the controller tests**

Run: `bin/rails test test/controllers/grades_controller_test.rb`
Expected: `4 runs` (2 existing + 2 new), `0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
hg add test/services/exporters/grade_distribution_exporter_test.rb
hg commit test/services/exporters/grade_distribution_exporter_test.rb test/controllers/grades_controller_test.rb -m "Test the grade-distribution CSV export

Lock in the export contract before it accretes users: column order mirrors the
on-screen table, Term appears only when split by semester, nil GPA/pass-rate
export as blank cells (not em-dashes), and the endpoint honors the same filters
as the HTML report (2103106 stays excluded under a 2110 prefix).

Unit tests cover the exporter against constructed rows; integration tests cover
the format.csv branch end-to-end against fixtures."
```
