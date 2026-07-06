# ChulaBooster Course + Grade Sync (Phase 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync CB's course catalog and 30,201 missing grades into the local DB, with audited COMMIT-gated corrections for known-stale local data (course placeholder shells, non-manual grade values).

**Architecture:** Two StudentSync-style services — `Chulabooster::CourseSync` (mirrors CB's `courses` export: create CB-only, backfill local shells, report real diffs) and `Chulabooster::GradeSync` (streams `student_courses` against in-memory indexes with a revision-insensitive identity key; corrects matched non-manual diffs, creates CB-only grades, resolves missing courses via an exact→copied→placeholder ladder). Each has a rake task with dry-run default / `COMMIT=1` / `SNAPSHOT_DIR=`.

**Tech Stack:** Ruby 3.4 / Rails 8.1, Minitest + fixtures, Mercurial.

**Spec:** `docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md` — read it before starting. The bucket numbers used in verification steps come from its "The landscape" table.

## Global Constraints

- **Version control is Mercurial, not git.** Commit with `hg add <files>` + `hg commit <explicit file list> -m "..."`. Never bare `hg commit` (the repo may carry unrelated dirty files). NEVER add or commit `config/credentials.yml.enc` or anything you did not create/modify for your task.
- **Commit messages lead with WHY** (first paragraph = motivation), then what changed.
- **NEVER run any rake task with `COMMIT=1`.** The dev DB holds the real production dataset (8,621 students). All verification runs are dry-run (the default). This is non-negotiable.
- Verification snapshot: `SNAPSHOT_DIR=tmp/chulabooster_snapshot/full-2026-07-03` (already on disk).
- Ruby style: match the existing `Chulabooster::*` services — endless methods where the codebase uses them, `module_function` Convert helpers, 2-space indent, double-quoted strings.
- Run tests with `bin/rails test <path>`; full suite `bin/rails test`.
- Per project preference, feature tests come **after** implementation (Tasks 5–6); the Task 2 regression test rides with its bug fix.

---

### Task 1: Grade source `"chulabooster"` (model + badge)

**Files:**
- Modify: `app/models/grade.rb:14-19`
- Modify: `app/assets/stylesheets/application.scss:212-213` (append after `.badge-manual`)

**Interfaces:**
- Produces: `Grade::SOURCES` includes `"chulabooster"`; `Grade::SOURCE_ICONS["chulabooster"]` = `"sync"`. Tasks 4 and 6 create/assert grades with `source: "chulabooster"`. Views already render sources data-driven (`badge-#{grade.source}` at `app/views/grades/index.html.haml:52` and `show.html.haml:69`), so only the SCSS class is needed — no view changes.

- [ ] **Step 1: Extend the model constants**

In `app/models/grade.rb`, change:

```ruby
  SOURCES = %w[imported manual].freeze

  SOURCE_ICONS = {
    "imported" => "cloud_download",
    "manual"   => "edit_note"
  }.freeze
```

to:

```ruby
  SOURCES = %w[imported manual chulabooster].freeze

  SOURCE_ICONS = {
    "imported"     => "cloud_download",
    "manual"       => "edit_note",
    "chulabooster" => "sync"
  }.freeze
```

- [ ] **Step 2: Add the badge class**

In `app/assets/stylesheets/application.scss`, directly below the `.badge-manual` line (~213), add:

```scss
.badge-chulabooster { background-color: rgba($info, 0.18);             color: $info;    border: 1px solid rgba($info, 0.4); }
```

(Frosted style per the badge conventions; `$info` distinguishes CB-synced from CSV-`imported` which uses `$primary`.)

- [ ] **Step 3: Rebuild CSS and verify**

Run: `bin/rails dartsass:build && grep -c "badge-chulabooster" app/assets/builds/application.css`
Expected: build succeeds, grep prints `1`.

Run: `bin/rails runner 'g = Grade.new(source: "chulabooster"); g.valid?; puts g.errors[:source].empty? ? "source accepted" : "REJECTED"'`
Expected: `source accepted`

- [ ] **Step 4: Commit**

```bash
hg commit app/models/grade.rb app/assets/stylesheets/application.scss -m "Add chulabooster grade source

Phase 2b (spec: docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md)
creates ~30k grades from the ChulaBooster registrar sync. A dedicated source value keeps
CB-synced rows permanently distinguishable from CSV imports for auditing, and lets future
correction logic target CB-sourced rows precisely.

- Grade::SOURCES + SOURCE_ICONS gain \"chulabooster\" (icon: sync)
- .badge-chulabooster frosted badge (views render badge-#{source} data-driven; no view changes)"
```

---

### Task 2: Fix GradeImporter placeholder branches (broken since M:N remodel)

**Files:**
- Modify: `app/services/importers/grade_importer.rb:69-77` and `:103-110`
- Create: `test/services/importers/grade_importer_test.rb`

**Interfaces:**
- Consumes: nothing from other tasks (independent bug fix).
- Produces: `GradeImporter#resolve_course(code)` and `#resolve_course_by_no(course_no, revision_year)` no longer raise on totally-unknown courses. Task 4's GradeSync implements its own ladder; this fix is for the CSV import path only.

**Context:** `Course` lost `belongs_to :program` in the Course↔Program M:N remodel, so both placeholder branches raise `ActiveModel::UnknownAttributeError: unknown attribute 'program' for Course` (verified 2026-07-05). Courses may now exist without program links.

- [ ] **Step 1: Write the failing regression test**

Create `test/services/importers/grade_importer_test.rb`:

```ruby
require "test_helper"

class Importers::GradeImporterTest < ActiveSupport::TestCase
  # resolve_course's placeholder branch raised UnknownAttributeError after the Course<->Program
  # M:N remodel removed Course#program=. Placeholders are now created program-less.
  test "resolve_course creates a program-less placeholder for a totally unknown course" do
    importer = Importers::GradeImporter.new(DataImport.new)
    course = nil
    assert_difference "Course.count", 1 do
      course = importer.send(:resolve_course, "20239999999")
    end
    assert_equal "9999999", course.course_no
    assert_equal 2566, course.revision_year_be  # 2023 CE -> BE
    assert_equal "placeholder", course.auto_generated
    assert_empty course.programs
  end

  test "resolve_course_by_no creates a program-less placeholder for an unknown course_no" do
    importer = Importers::GradeImporter.new(DataImport.new)
    course = nil
    assert_difference "Course.count", 1 do
      course = importer.send(:resolve_course_by_no, "8888888", -1)
    end
    assert_equal "8888888", course.course_no
    assert_equal(-1, course.revision_year_be)
    assert_equal "placeholder", course.auto_generated
    assert_empty course.programs
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/importers/grade_importer_test.rb`
Expected: 2 failures/errors — `ActiveModel::UnknownAttributeError: unknown attribute 'program' for Course.`

- [ ] **Step 3: Fix both branches**

In `app/services/importers/grade_importer.rb`, in `resolve_course_by_no`, change:

```ruby
      Course.create!(
        course_no: course_no,
        revision_year_be: revision_year,
        name: course_no,
        program: Program.placeholder,
        auto_generated: "placeholder"
      )
```

to:

```ruby
      # Program-less: Course lost program= in the M:N remodel; placeholder courses
      # carry no program links until a human (or a future sync) assigns them.
      Course.create!(
        course_no: course_no,
        revision_year_be: revision_year,
        name: course_no,
        auto_generated: "placeholder"
      )
```

Make the identical change in `resolve_course` (the second `Course.create!` block, ~line 103).

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/importers/grade_importer_test.rb`
Expected: `2 runs, ... 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```bash
hg add test/services/importers/grade_importer_test.rb
hg commit app/services/importers/grade_importer.rb test/services/importers/grade_importer_test.rb -m "Fix GradeImporter placeholder branches broken by the Course-Program M:N remodel

Both resolve_course fallbacks still passed program: to Course.create!, but Course lost
program= when the 1:N became M:N via ProgramCourse — any CSV grade import hitting a
totally-unknown course raised UnknownAttributeError at runtime. Found while designing the
Phase 2b CB grade sync, which reimplements this ladder.

- drop program: from both placeholder Course.create! calls (courses may be program-less)
- regression tests for resolve_course and resolve_course_by_no placeholder branches"
```

---

### Task 3: `Chulabooster::CourseSync` + `chulabooster:sync_courses` rake task

**Files:**
- Create: `app/services/chulabooster/course_sync.rb`
- Modify: `lib/tasks/chulabooster.rake` (append task inside the `:chulabooster` namespace)
- Modify: `docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md` (one-line amendment: `name_abbr` joins the synced field set)

**Interfaces:**
- Consumes: `Chulabooster::Convert` (`ce_to_be`, `int_or_nil`, `bool`, `norm`) — exists; `Client`/`SnapshotClient#each_row("courses")` — exists.
- Produces: `Chulabooster::CourseSync.new(client:, run_dir:, commit: false)` / `#call` → counts Hash with keys `:cb_rows, :matched_real, :backfilled/:backfillable, :created/:creatable, :discrepancies, :errors`. Task 5 tests this exact interface. GradeSync (Task 4) does not call CourseSync — coupling is by run order only.

- [ ] **Step 1: Amend the spec's synced field set**

In the spec, section "1. `Chulabooster::CourseSync`", the CB-only create bullet currently reads `… `name_th` ← `course_name_alt`,`. Change that line to include the abbreviation:

```
- **CB-only → create** with full metadata: `name` ← `course_name`, `name_th` ← `course_name_alt`,
  `name_abbr` ← `course_name_abbr` (exported by CB, column exists locally; not compared for
  discrepancies),
```

- [ ] **Step 2: Write the service**

Create `app/services/chulabooster/course_sync.rb`:

```ruby
require "csv"
require "fileutils"

module Chulabooster
  # Phase 2b write path, courses half: mirrors CB's `courses` export into the local catalog.
  # Three buckets per CB row:
  #   CB-only                            -> create with full metadata      (COMMIT-gated)
  #   matched, local auto_generated shell -> backfill from CB, flip "none"  (COMMIT-gated)
  #   matched, local real row             -> field diffs report-only, never written
  # Local-only courses are never touched. Dry-run (default) computes everything, writes CSVs only.
  # Policy + evidence: docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md
  class CourseSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      local = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      counts = Hash.new(0)
      rows = { created: [], backfilled: [], disc: [], errors: [] }

      @client.each_row("courses") do |row|
        counts[:cb_rows] += 1
        key = [row["course_no"].to_s, Convert.ce_to_be(row["revision_year"])]
        course = local[key]
        if course.nil?
          create_course(key, row, counts, rows)
        elsif course.auto_generated != "none"
          backfill_course(course, row, counts, rows)
        else
          report_diffs(course, row, counts, rows)
        end
      end

      write_csv("created_courses.csv", %w[course_no revision_year_be name credits], rows[:created])
      write_csv("backfilled_courses.csv", %w[course_no revision_year_be field old new], rows[:backfilled])
      write_csv("course_discrepancies.csv", %w[course_no revision_year_be field local cb], rows[:disc])
      write_csv("row_errors.csv", %w[course_no revision_year_be errors], rows[:errors])
      counts
    end

    private

    # The synced field set, applied on create AND backfill. name_abbr rides along (CB exports
    # it, the column exists locally) but is excluded from discrepancy comparison — see
    # COMPARED_FIELDS. nl_credits/description stay nil: CB doesn't export the former and the
    # latter is null throughout the export.
    def cb_attributes(row)
      {
        name:      row["course_name"].to_s.strip,
        name_th:   row["course_name_alt"].to_s.strip.presence,
        name_abbr: row["course_name_abbr"].to_s.strip.presence,
        credits:   Convert.int_or_nil(row["credits"]),
        l_credits: Convert.int_or_nil(row["l_credits"]),
        l_hours:   Convert.int_or_nil(row["l_hours"]),
        nl_hours:  Convert.int_or_nil(row["nl_hours"]),
        s_hours:   Convert.int_or_nil(row["s_hours"]),
        is_thesis: Convert.bool(row["is_thesis"]),
        is_gened:  Convert.bool(row["gened"])
      }
    end

    COMPARED_FIELDS = %i[name name_th credits l_credits l_hours nl_hours s_hours
                         is_thesis is_gened].freeze

    def create_course(key, row, counts, rows)
      course = Course.new(course_no: key[0], revision_year_be: key[1],
                          auto_generated: "none", **cb_attributes(row))
      ok = @commit ? course.save : course.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [key[0], key[1], course.errors.full_messages.join("; ")]
        return
      end
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [key[0], key[1], course.name, course.credits]
    end

    # Local shells (auto_generated "placeholder"/"copied") hold no real data — the 2026-07-05
    # crosswalk found every matched-changed course was one of ours. CB's registrar metadata
    # replaces the shell and the row is promoted to auto_generated "none".
    def backfill_course(course, row, counts, rows)
      attrs = cb_attributes(row)
      changes = attrs.filter_map do |field, new_value|
        old_value = course.public_send(field)
        [course.course_no, course.revision_year_be, field, old_value, new_value] if old_value != new_value
      end
      course.assign_attributes(**attrs, auto_generated: "none")
      ok = @commit ? course.save : course.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [course.course_no, course.revision_year_be,
                          course.errors.full_messages.join("; ")]
        course.restore_attributes
        return
      end
      course.restore_attributes unless @commit
      counts[@commit ? :backfilled : :backfillable] += 1
      rows[:backfilled].concat(changes)
    end

    # Real local rows are authoritative: report, never write. (Crosswalk: 65/65 currently
    # identical, so this file is expected empty.)
    def report_diffs(course, row, counts, rows)
      counts[:matched_real] += 1
      cb_attributes(row).slice(*COMPARED_FIELDS).each do |field, cb_value|
        local_value = course.public_send(field)
        next if Convert.norm(local_value) == Convert.norm(cb_value)
        counts[:discrepancies] += 1
        rows[:disc] << [course.course_no, course.revision_year_be, field, local_value, cb_value]
      end
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
```

- [ ] **Step 3: Add the rake task**

In `lib/tasks/chulabooster.rake`, append inside `namespace :chulabooster do` (after `sync_students`):

```ruby
  desc "Create CB-only Courses + backfill local auto-generated shells from CB metadata. " \
       "DRY-RUN by default; COMMIT=1 to write. SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_courses: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync_courses", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — courses WILL be created/backfilled" : "MODE: dry-run — no database writes"
    counts = Chulabooster::CourseSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "cb rows:                #{counts[:cb_rows]}"
    puts "matched (real):         #{counts[:matched_real]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "#{commit ? 'backfilled:            ' : 'backfillable:          '} #{counts[commit ? :backfilled : :backfillable]}"
    puts "discrepancies (real):   #{counts[:discrepancies]}   <- review course_discrepancies.csv"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
```

- [ ] **Step 4: Verify with an offline dry-run against the real snapshot**

Run: `SNAPSHOT_DIR=tmp/chulabooster_snapshot/full-2026-07-03 bin/rails chulabooster:sync_courses`
Expected (must match the spec's landscape exactly):

```
cb rows:                262
matched (real):         3
creatable:              180
backfillable:           79
discrepancies (real):   0
row errors:             0
```

(Numbers corrected 2026-07-06: the 82 matched courses split 3 real / 63 "copied" clones / 16
placeholders; the user decided clones are backfilled like placeholders. An earlier draft said
65/17 by wrongly equating field-identical with real.)

Then confirm the dry run wrote nothing: `bin/rails runner 'puts Course.count'` must print the same value before and after (capture it before the run). Inspect `backfilled_courses.csv` — 79 courses' worth of field rows; old values are placeholder stubs (name = course_no, nils) or clone guesses. Confirm it contains a `2110471,2539,name,COMPUTER NETWORKS I,COMPUTER ARCHITECTURE` row — the known wrong clone being fixed.

If any number differs, STOP and report the discrepancy — do not "fix" the expectation.

- [ ] **Step 5: Commit**

```bash
hg add app/services/chulabooster/course_sync.rb
hg commit app/services/chulabooster/course_sync.rb lib/tasks/chulabooster.rake -m "Add CourseSync: mirror CB course export, backfill auto-generated course rows

The Jul-3 crosswalk showed the course gap is one-sided: CB has 180 courses we lack (full
registrar metadata), and every matched-changed row is machine-invented — 16 placeholder
stubs plus a \"copied\" clone whose guessed name is provably wrong (2110471 rev 2539:
course-number reuse). The 3 real local courses agree with CB 100%. So the sync is additive
plus one audited correction class: all auto-generated rows (63 clones + 16 placeholders)
are backfilled from CB and promoted to auto_generated \"none\"; real-row diffs stay
report-only.

- Chulabooster::CourseSync (create / backfill / report buckets, per-run CSV reports)
- chulabooster:sync_courses rake task (dry-run default, COMMIT=1, SNAPSHOT_DIR=)
- verified against the Jul-3 snapshot: 262 rows -> 3 matched-real / 180 creatable / 79
  backfillable / 0 discrepancies"
```

(The spec amendments — name_abbr field-set addition and the corrected crosswalk evidence —
are committed separately by the controller; this commit is code only.)

---

### Task 4: `Chulabooster::GradeSync` + `chulabooster:sync_grades` rake task

**Files:**
- Create: `app/services/chulabooster/grade_sync.rb`
- Modify: `lib/tasks/chulabooster.rake` (append after `sync_courses`)

**Interfaces:**
- Consumes: `Convert.parse_course_id`, `Convert.semester_number`, `Convert.int_or_nil`; `Grade::GRADE_WEIGHTS`; `source: "chulabooster"` from Task 1; `each_row("student_courses")`.
- Produces: `Chulabooster::GradeSync.new(client:, run_dir:, commit: false)` / `#call` → counts Hash with keys `:cb_rows, :sentinel, :unknown_student, :matched, :identical, :corrected/:correctable, :manual_diff, :value_to_nil, :created/:creatable, :ladder_copied, :ladder_placeholder, :duplicate_cb, :errors`. Task 6 tests this exact interface.

- [ ] **Step 1: Write the service**

Create `app/services/chulabooster/grade_sync.rb`:

```ruby
require "csv"
require "fileutils"
require "set"

module Chulabooster
  # Phase 2b write path, grades half. Streams CB's `student_courses` export against in-memory
  # indexes. Identity key is REVISION-INSENSITIVE — (student_id, course_no, year_ce, semester) —
  # because course_no is the project's cross-revision course identity and 2,181 CB rows
  # reference a different revision of an enrollment we already have (full-key matching would
  # import those as duplicate enrollments). Existing grades are never re-linked to another
  # course revision; only values are corrected.
  #
  # Buckets:
  #   sentinel course_id (FOR_ETL etc.)      -> skip + count
  #   unknown student (non-dept, no CB data) -> skip + report CSV
  #   matched, values identical              -> count
  #   matched, local source "manual"         -> report-only (human data wins)
  #   matched, CB grade blank                -> report-only (never blank local values)
  #   matched, otherwise                     -> CORRECT to CB value (COMMIT-gated; CB is the
  #                                             registrar of record for grade values)
  #   CB-only                                -> create (COMMIT-gated), course via ladder:
  #                                             exact -> closest-revision copy -> placeholder
  # Policy + evidence: docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md
  class GradeSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      build_indexes
      counts = Hash.new(0)
      rows = { created: [], corrections: [], disc: [], skipped: [], ladder: [], errors: [] }

      @client.each_row("student_courses") do |row|
        counts[:cb_rows] += 1
        process_row(row, counts, rows)
      end

      write_csv("created_grades.csv",
                %w[student_id course_no revision_year_be year_ce semester grade credits_grant],
                rows[:created])
      write_csv("grade_corrections.csv",
                %w[student_id course_no year_ce semester old_grade new_grade old_credits_grant new_credits_grant source],
                rows[:corrections])
      write_csv("grade_discrepancies.csv",
                %w[student_id course_no year_ce semester local_grade cb_grade reason], rows[:disc])
      write_csv("skipped_unknown_students.csv",
                %w[student_id course_no year_ce semester grade], rows[:skipped])
      write_csv("ladder_courses.csv",
                %w[course_no revision_year_be kind source_revision_year_be], rows[:ladder])
      write_csv("row_errors.csv", %w[student_id course_no year_ce semester errors], rows[:errors])
      counts
    end

    private

    def build_indexes
      @students = Student.all.index_by { |s| s.student_id.to_s }
      @courses  = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      @by_no    = @courses.values.group_by { |c| c.course_no.to_s }
      @grades   = {}
      Grade.includes(:student, :course).find_each do |g|
        @grades[[g.student.student_id.to_s, g.course.course_no.to_s, g.year_ce, g.semester]] = g
      end
      @created_keys = Set.new
    end

    def process_row(row, counts, rows)
      unless row["course_id"].to_s.match?(/\A\d{4}\d+\z/)
        counts[:sentinel] += 1 # e.g. the FOR_ETL row
        return
      end
      course_no, rev_be = Convert.parse_course_id(row["course_id"])
      sid      = row["student_id"].to_s
      year     = Convert.int_or_nil(row["academic_year"]) # already C.E. — no era conversion
      semester = Convert.semester_number(row["semester_code"])
      key      = [sid, course_no, year, semester]

      student = @students[sid]
      unless student
        # Non-department students absent from CB's own students export — no name/program
        # available, so no Student row can be built. Reported, not imported.
        counts[:unknown_student] += 1
        rows[:skipped] << [sid, course_no, year, semester, row["grade"]]
        return
      end

      if (grade = @grades[key])
        check_matched(grade, row, counts, rows)
      else
        create_grade(key, rev_be, student, row, counts, rows)
      end
    end

    def check_matched(grade, row, counts, rows)
      counts[:matched] += 1
      cb_grade = row["grade"].to_s.strip.presence
      # CB reports credits_grant 0.0 for not-yet-graded enrollments; importing that as
      # "earned 0" would be wrong, so a blank grade forces nil credits.
      cb_credits = cb_grade ? Convert.int_or_nil(row["credits_grant"]) : nil

      if grade.grade == cb_grade && grade.credits_grant == cb_credits
        counts[:identical] += 1
      elsif grade.source == "manual"
        counts[:manual_diff] += 1
        rows[:disc] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                        grade.semester, grade.grade, cb_grade, "manual"]
      elsif cb_grade.nil?
        counts[:value_to_nil] += 1
        rows[:disc] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                        grade.semester, grade.grade, nil, "value_to_nil"]
      else
        correct(grade, cb_grade, cb_credits, counts, rows)
      end
    end

    # CB is the registrar of record for grade values on non-manual rows (crosswalk: the 22
    # current diffs are local interim codes vs CB's resolved finals). nil->value fills the
    # in-progress enrollments this sync creates, on the run after CB grades them.
    def correct(grade, cb_grade, cb_credits, counts, rows)
      rows[:corrections] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                             grade.semester, grade.grade, cb_grade, grade.credits_grant,
                             cb_credits, grade.source]
      unless @commit
        counts[:correctable] += 1
        return
      end
      if grade.update(grade: cb_grade, grade_weight: Grade::GRADE_WEIGHTS[cb_grade],
                      credits_grant: cb_credits)
        counts[:corrected] += 1
      else
        counts[:errors] += 1
        rows[:errors] << [grade.student.student_id, grade.course.course_no, grade.year_ce,
                          grade.semester, grade.errors.full_messages.join("; ")]
      end
    end

    def create_grade(key, rev_be, student, row, counts, rows)
      sid, course_no, year, semester = key
      if @created_keys.include?(key)
        counts[:duplicate_cb] += 1
        rows[:errors] << [sid, course_no, year, semester, "duplicate CB row"]
        return
      end

      course = resolve_course(course_no, rev_be, counts, rows)
      cb_grade = row["grade"].to_s.strip.presence
      grade = Grade.new(
        student: student, course: course, year_ce: year, semester: semester,
        grade: cb_grade,
        grade_weight: cb_grade && Grade::GRADE_WEIGHTS[cb_grade],
        credits_grant: cb_grade ? Convert.int_or_nil(row["credits_grant"]) : nil,
        source: "chulabooster"
      )
      ok = @commit ? grade.save : grade.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [sid, course_no, year, semester, grade.errors.full_messages.join("; ")]
        return
      end
      @created_keys << key
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [sid, course_no, course.revision_year_be, year, semester,
                         cb_grade, grade.credits_grant]
    end

    # Exact -> closest-revision copy -> minimal placeholder (the CSV GradeImporter convention,
    # without its program: bug). In dry-run the course is built but not saved; the Grade
    # validity check works against the unsaved object, and the in-memory indexes are updated
    # either way so each missing course is resolved (and reported) exactly once.
    def resolve_course(course_no, rev_be, counts, rows)
      exact = @courses[[course_no, rev_be]]
      return exact if exact

      siblings = @by_no[course_no]
      course =
        if siblings&.any?
          src = siblings.min_by { |c| (c.revision_year_be - rev_be).abs }
          counts[:ladder_copied] += 1
          rows[:ladder] << [course_no, rev_be, "copied", src.revision_year_be]
          src.dup.tap { |c| c.revision_year_be = rev_be; c.auto_generated = "copied" }
        else
          counts[:ladder_placeholder] += 1
          rows[:ladder] << [course_no, rev_be, "placeholder", nil]
          Course.new(course_no: course_no, revision_year_be: rev_be, name: course_no,
                     auto_generated: "placeholder")
        end
      course.save! if @commit
      @courses[[course_no, rev_be]] = course
      (@by_no[course_no] ||= []) << course
      course
    end

    def write_csv(name, header, data_rows)
      CSV.open(File.join(@run_dir, name), "w") do |csv|
        csv << header
        data_rows.each { |r| csv << r }
      end
    end
  end
end
```

- [ ] **Step 2: Add the rake task**

In `lib/tasks/chulabooster.rake`, append after `sync_courses`:

```ruby
  desc "Create CB-only Grades + correct stale non-manual grade values from CB (registrar of " \
       "record). Run sync_courses first. DRY-RUN by default; COMMIT=1 to write. " \
       "SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_grades: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync_grades", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — grades WILL be created/corrected" : "MODE: dry-run — no database writes"
    counts = Chulabooster::GradeSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "cb rows:                #{counts[:cb_rows]}"
    puts "sentinel course_id:     #{counts[:sentinel]}"
    puts "unknown students:       #{counts[:unknown_student]}   <- skipped_unknown_students.csv"
    puts "matched:                #{counts[:matched]}"
    puts "  identical:            #{counts[:identical]}"
    puts "#{commit ? '  corrected:           ' : '  correctable:         '} #{counts[commit ? :corrected : :correctable]}   <- grade_corrections.csv"
    puts "  manual diffs:         #{counts[:manual_diff]}   <- grade_discrepancies.csv"
    puts "  value->nil diffs:     #{counts[:value_to_nil]}   <- grade_discrepancies.csv"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "  ladder copied:        #{counts[:ladder_copied]}   <- ladder_courses.csv"
    puts "  ladder placeholder:   #{counts[:ladder_placeholder]}"
    puts "duplicate CB rows:      #{counts[:duplicate_cb]}"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
```

- [ ] **Step 3: Verify with an offline dry-run against the real snapshot**

Run: `SNAPSHOT_DIR=tmp/chulabooster_snapshot/full-2026-07-03 bin/rails chulabooster:sync_grades`
Expected (from the spec's landscape table; run takes a few minutes):

```
cb rows:                49502
sentinel course_id:     1
unknown students:       3876
matched:                15424
  identical:            15402
  correctable:          22
  manual diffs:         0
  value->nil diffs:     0
creatable:              30201
  ladder copied:        20
  ladder placeholder:   145
duplicate CB rows:      0
row errors:             0
```

Then confirm nothing was written: `bin/rails runner 'puts [Grade.count, Course.count].inspect'` unchanged from before the run. Spot-check `grade_corrections.csv`: 22 rows, old grades mostly `M`/`I`/`X`/`S`, new grades letter finals.

If any number differs, STOP and report — do not adjust expectations to match.

- [ ] **Step 4: Commit**

```bash
hg add app/services/chulabooster/grade_sync.rb
hg commit app/services/chulabooster/grade_sync.rb lib/tasks/chulabooster.rake -m "Add GradeSync: import CB-only grades, correct stale non-manual values

The reconciliation's \"36k missing grades\" decomposed into 30,201 creatable rows, 3,876
rows of non-department students CB itself can't describe (skip+report), one ETL sentinel,
and 2,181 revision-shadowed rows that naive full-key matching would have imported as
duplicate enrollments — hence a revision-insensitive identity key
(student_id, course_no, year_ce, semester). Where matched values differ (22 rows), local
holds interim registrar codes (M/I/X/S) against CB's resolved finals — the same stale-local
asymmetry as Phase 2a's status field — so non-manual grade values are corrected to CB's,
audited in grade_corrections.csv; manual rows and CB-blank-vs-local-value stay report-only.

- Chulabooster::GradeSync (sentinel/unknown-student/matched/CB-only buckets, course ladder
  exact -> copied -> placeholder, per-run CSV reports)
- chulabooster:sync_grades rake task (dry-run default, COMMIT=1, SNAPSHOT_DIR=)
- verified against the Jul-3 snapshot: 49,502 rows -> 15,424 matched (22 correctable),
  30,201 creatable (20 copied + 145 placeholder ladder courses), 3,876 skipped, 0 errors"
```

---

### Task 5: CourseSync tests

**Files:**
- Create: `test/services/chulabooster/course_sync_test.rb`

**Interfaces:**
- Consumes: `Chulabooster::CourseSync.new(client:, run_dir:, commit:)` → counts keys `:cb_rows, :matched_real, :backfilled/:backfillable, :created/:creatable, :discrepancies, :errors` (Task 3); fixtures `courses(:intro_computing)` (2110101, rev 2565, credits 3, s_hours 6).

- [ ] **Step 1: Write the tests**

Create `test/services/chulabooster/course_sync_test.rb`:

```ruby
require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::CourseSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("course-sync-test")
    # A local auto-generated shell, as the CSV GradeImporter ladder creates them.
    @shell = Course.create!(course_no: "2110502", revision_year_be: 2557,
                            name: "2110502", auto_generated: "placeholder")
    # A "copied" clone whose guessed name is wrong (the 2110471 course-number-reuse case) —
    # user decision 2026-07-06: clones are backfilled like placeholders.
    @clone = Course.create!(course_no: "2110471", revision_year_be: 2539,
                            name: "COMPUTER NETWORKS I", credits: 3, l_credits: 3,
                            auto_generated: "copied")
    @real = courses(:intro_computing)
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # Builds a CB export row that mirrors a local course exactly (identical under comparison).
  # CB sends CE years and float numerics; names compare case-insensitively via Convert.norm.
  def cb_row_for(course, **overrides)
    { "course_no"        => course.course_no,
      "revision_year"    => course.revision_year_be - 543,
      "course_name"      => course.name.to_s.upcase,
      "course_name_alt"  => course.name_th,
      "course_name_abbr" => course.name_abbr,
      "credits"          => course.credits&.to_f,
      "l_credits"        => course.l_credits&.to_f,
      "l_hours"          => course.l_hours&.to_f,
      "nl_hours"         => course.nl_hours&.to_f,
      "s_hours"          => course.s_hours&.to_f,
      "is_thesis"        => course.is_thesis ? 1.0 : 0.0,
      "gened"            => course.is_gened ? 1 : nil }.merge(overrides)
  end

  def cb_rows
    [
      cb_row_for(@real),                                       # matched real, identical
      cb_row_for(@real, "credits" => 4.0),                     # 2nd row for same course: real diff
      cb_row_for(@shell, "course_name" => "FORMAL VERIFICATION",
                 "course_name_alt" => "การทวนสอบเชิงรูปนัย",
                 "course_name_abbr" => "FORMAL VER",
                 "credits" => 3.0, "l_credits" => 3.0, "l_hours" => 3.0,
                 "nl_hours" => 0.0, "s_hours" => 0.0),          # shell -> backfill
      cb_row_for(@clone, "course_name" => "COMPUTER ARCHITECTURE",
                 "course_name_alt" => "สถาปัตยกรรมคอมพิวเตอร์"), # divergent clone -> backfill fixes name
      { "course_no" => "2110999", "revision_year" => 2023,
        "course_name" => "NEW COURSE", "course_name_alt" => "วิชาใหม่",
        "course_name_abbr" => "NEW C", "credits" => 3.0, "l_credits" => 3.0,
        "l_hours" => 3.0, "nl_hours" => 0.0, "s_hours" => 0.0,
        "is_thesis" => 0.0, "gened" => nil }                    # CB-only -> create
    ]
  end

  test "dry-run computes everything and writes NOTHING to the database" do
    counts = nil
    assert_no_difference "Course.count" do
      counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir).call
    end

    assert_equal 5, counts[:cb_rows]
    assert_equal 2, counts[:matched_real] # identical row + the credits-diff row
    assert_equal 1, counts[:creatable]
    assert_equal 0, counts[:created]
    assert_equal 2, counts[:backfillable] # shell + divergent clone
    assert_equal 1, counts[:discrepancies]
    assert_equal 0, counts[:errors]

    @shell.reload
    assert_equal "2110502", @shell.name, "dry-run must not backfill"
    assert_equal "placeholder", @shell.auto_generated
    @clone.reload
    assert_equal "COMPUTER NETWORKS I", @clone.name, "dry-run must not backfill clones"
    assert_equal "copied", @clone.auto_generated
    assert_equal 3, @real.reload.credits, "real rows are never written"

    disc = CSV.read(File.join(@dir, "course_discrepancies.csv"))[1..]
    assert_equal [["2110101", "2565", "credits", "3", "4"]], disc
  end

  test "commit creates CB-only courses and backfills shells, promoting them to none" do
    counts = nil
    assert_difference "Course.count", 1 do
      counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir,
                                            commit: true).call
    end
    assert_equal 1, counts[:created]
    assert_equal 2, counts[:backfilled]

    created = Course.find_by!(course_no: "2110999", revision_year_be: 2566) # 2023 CE -> BE
    assert_equal "NEW COURSE", created.name
    assert_equal "วิชาใหม่", created.name_th
    assert_equal 3, created.credits            # float coerced to int
    assert_equal "none", created.auto_generated
    assert_not created.is_thesis
    assert_empty created.programs

    @shell.reload
    assert_equal "FORMAL VERIFICATION", @shell.name
    assert_equal "การทวนสอบเชิงรูปนัย", @shell.name_th
    assert_equal 3, @shell.credits
    assert_equal "none", @shell.auto_generated, "backfilled shell is promoted"

    @clone.reload
    assert_equal "COMPUTER ARCHITECTURE", @clone.name, "registrar data replaces the clone guess"
    assert_equal "none", @clone.auto_generated, "backfilled clone is promoted"

    assert_equal 3, @real.reload.credits, "real-row diff is report-only even in commit"
  end

  test "commit run is idempotent — second run creates and backfills nothing" do
    Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    dir2 = Dir.mktmpdir("course-sync-test-2")
    begin
      counts = nil
      assert_no_difference "Course.count" do
        counts = Chulabooster::CourseSync.new(client: FakeClient.new(cb_rows), run_dir: dir2,
                                              commit: true).call
      end
      assert_equal 0, counts[:created]
      assert_equal 0, counts[:backfilled], "backfilled rows are now real rows"
      assert_equal 5, counts[:matched_real] # identical + diff-row + ex-shell + ex-clone + created
    ensure
      FileUtils.remove_entry(dir2)
    end
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `bin/rails test test/services/chulabooster/course_sync_test.rb`
Expected: `3 runs, ... 0 failures, 0 errors`. If a count assertion fails, debug the SERVICE (or a fixture drift), not the test — the counts encode the spec.

- [ ] **Step 3: Commit**

```bash
hg add test/services/chulabooster/course_sync_test.rb
hg commit test/services/chulabooster/course_sync_test.rb -m "Test CourseSync bucket routing and write gates

Covers the three buckets (create / shell backfill / real-row report-only), the dry-run
zero-writes invariant, float->int coercion, auto_generated promotion on backfill, and
commit idempotence — the same invariant set that guards StudentSync."
```

---

### Task 6: GradeSync tests

**Files:**
- Create: `test/services/chulabooster/grade_sync_test.rb`

**Interfaces:**
- Consumes: `Chulabooster::GradeSync.new(client:, run_dir:, commit:)` → counts keys `:cb_rows, :sentinel, :unknown_student, :matched, :identical, :corrected/:correctable, :manual_diff, :value_to_nil, :created/:creatable, :ladder_copied, :ladder_placeholder, :duplicate_cb, :errors` (Task 4); fixtures `grades(:active_intro_computing)` (A, imported, 2024 s1), `grades(:graduated_intro_computing)` (A, imported, 2022 s1), `grades(:active_gened)` (B, manual, 2024 s1), `grades(:active_senior_project)` (B+, imported, 2024 s2), `students(:active_student)` (6732100021), `students(:graduated_student)`, `courses(:intro_computing)` (2110101 rev 2565), `courses(:senior_project)` (2110499 rev 2565).

- [ ] **Step 1: Write the tests**

Create `test/services/chulabooster/grade_sync_test.rb`:

```ruby
require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::GradeSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("grade-sync-test")
    # An in-progress enrollment (nil grade) as this sync itself creates them — the
    # nil->value fill path.
    @in_progress = Grade.create!(student: students(:graduated_student),
                                 course: courses(:senior_project),
                                 year_ce: 2023, semester: 1, grade: nil, source: "imported")
    @identical  = grades(:active_intro_computing)   # A, imported, 2024 s1
    @stale      = grades(:graduated_intro_computing) # A, imported, 2022 s1 -> CB says B
    @manual     = grades(:active_gened)              # B, manual, 2024 s1  -> CB says A
    @to_nil     = grades(:active_senior_project)     # B+, imported, 2024 s2 -> CB blank
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # CB student_courses row. course_id = "<CE revision year><course_no>"; semester_code is
  # "S1"/"s2"-style; credits_grant arrives as a float.
  def cb_row(grade_or_nil = nil, student: nil, course: nil, year: nil, semester: nil,
             cb_grade:, credits_grant: nil, revision_year_be: nil, course_no: nil)
    g = grade_or_nil
    student ||= g.student
    course_no ||= (course || g.course).course_no
    rev_be = revision_year_be || (course || g.course).revision_year_be
    { "course_id"     => "#{rev_be - 543}#{course_no}",
      "student_id"    => student.student_id,
      "academic_year" => year || g&.year_ce,
      "semester_code" => "S#{semester || g&.semester}",
      "grade"         => cb_grade,
      "credits_grant" => credits_grant }
  end

  def cb_rows
    new_enrollment = cb_row(student: students(:active_student), course: courses(:intro_computing),
                            year: 2025, semester: 1, cb_grade: "", credits_grant: 0.0)
    [
      cb_row(@identical, cb_grade: "A"),                                    # identical
      cb_row(@stale, cb_grade: "B", credits_grant: 3.0),                    # value->value correct
      cb_row(@in_progress, cb_grade: "A", credits_grant: 3.0),              # nil->value fill
      cb_row(@manual, cb_grade: "A", credits_grant: 3.0),                   # manual -> report only
      cb_row(@to_nil, cb_grade: ""),                                        # value->nil -> report only
      { "course_id" => "FOR_ETL", "student_id" => students(:active_student).student_id,
        "academic_year" => 2016, "semester_code" => "S2", "grade" => "",
        "credits_grant" => 0.0 },                                           # sentinel
      cb_row(student: students(:active_student), course: courses(:intro_computing),
             year: 2023, semester: 2, cb_grade: "D", credits_grant: 3.0,
             revision_year_be: 2566),                                       # matched IGNORING revision?
      # ^ no: (active_student, 2110101, 2023, 2) has no local grade -> CB-only, but rev 2566
      #   doesn't exist locally -> ladder copies closest revision (2565).
      cb_row(student: students(:graduated_student), year: 2022, semester: 2, cb_grade: "C+",
             credits_grant: 3.0, course_no: "5500111", course: nil,
             revision_year_be: 2566),                                       # CB-only, unknown course -> placeholder
      new_enrollment,                                                       # CB-only, blank grade
      new_enrollment.dup,                                                   # duplicate CB row
      cb_row(student: Student.new(student_id: "1111111111"),
             course: courses(:intro_computing), year: 2024, semester: 1,
             cb_grade: "A", credits_grant: 3.0)                             # unknown student
    ]
  end

  test "dry-run computes everything and writes NOTHING to the database" do
    counts = nil
    assert_no_difference ["Grade.count", "Course.count"] do
      counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir).call
    end

    assert_equal 11, counts[:cb_rows]
    assert_equal 1, counts[:sentinel]
    assert_equal 1, counts[:unknown_student]
    assert_equal 5, counts[:matched]
    assert_equal 1, counts[:identical]
    assert_equal 2, counts[:correctable] # stale value->value + nil->value fill
    assert_equal 0, counts[:corrected]
    assert_equal 1, counts[:manual_diff]
    assert_equal 1, counts[:value_to_nil]
    assert_equal 3, counts[:creatable]   # copied-ladder D, placeholder C+, blank enrollment
    assert_equal 1, counts[:ladder_copied]
    assert_equal 1, counts[:ladder_placeholder]
    assert_equal 1, counts[:duplicate_cb]
    assert_equal 0, counts[:errors]

    assert_equal "A", @stale.reload.grade, "dry-run must not correct"
    assert_nil @in_progress.reload.grade, "dry-run must not fill"

    corrections = CSV.read(File.join(@dir, "grade_corrections.csv"))[1..]
    assert_equal 2, corrections.length
    disc = CSV.read(File.join(@dir, "grade_discrepancies.csv"))[1..]
    assert_equal %w[manual value_to_nil], disc.map(&:last).sort
    skipped = CSV.read(File.join(@dir, "skipped_unknown_students.csv"))[1..]
    assert_equal [["1111111111", "2110101", "2024", "1", "A"]], skipped
    ladder = CSV.read(File.join(@dir, "ladder_courses.csv"))[1..]
    assert_equal [["2110101", "2566", "copied", "2565"], ["5500111", "2566", "placeholder", nil]],
                 ladder
  end

  test "commit corrects stale values, fills nil grades, creates CB-only rows, protects manual" do
    counts = nil
    assert_difference "Grade.count", 3 do
      assert_difference "Course.count", 2 do
        counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir,
                                             commit: true).call
      end
    end
    assert_equal 2, counts[:corrected]
    assert_equal 3, counts[:created]

    @stale.reload
    assert_equal "B", @stale.grade
    assert_equal 3.0, @stale.grade_weight.to_f
    assert_equal 3, @stale.credits_grant
    assert_equal courses(:intro_computing), @stale.course, "never re-linked to another revision"

    @in_progress.reload
    assert_equal "A", @in_progress.grade
    assert_equal 4.0, @in_progress.grade_weight.to_f

    assert_equal "B", @manual.reload.grade, "manual rows are never modified"
    assert_equal "B+", @to_nil.reload.grade, "CB blank never blanks a local value"

    copied = Course.find_by!(course_no: "2110101", revision_year_be: 2566)
    assert_equal "copied", copied.auto_generated
    assert_equal courses(:intro_computing).name, copied.name

    placeholder = Course.find_by!(course_no: "5500111", revision_year_be: 2566)
    assert_equal "placeholder", placeholder.auto_generated
    assert_equal "5500111", placeholder.name
    assert_empty placeholder.programs

    blank = Grade.find_by!(student: students(:active_student),
                           course: courses(:intro_computing), year_ce: 2025, semester: 1)
    assert_nil blank.grade
    assert_nil blank.credits_grant, "CB's 0.0 for in-progress must not become earned-0"
    assert_equal "chulabooster", blank.source
  end

  test "commit run is idempotent — second run corrects and creates nothing" do
    Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: @dir, commit: true).call
    dir2 = Dir.mktmpdir("grade-sync-test-2")
    begin
      counts = nil
      assert_no_difference ["Grade.count", "Course.count"] do
        counts = Chulabooster::GradeSync.new(client: FakeClient.new(cb_rows), run_dir: dir2,
                                             commit: true).call
      end
      assert_equal 0, counts[:corrected]
      assert_equal 0, counts[:created]
      # matched = 11 rows - 1 sentinel - 1 unknown student = 9: the 5 originally-matched keys,
      # the 3 rows created by run 1, and the former duplicate row (now just another matched hit).
      assert_equal 9, counts[:matched]
      # identical = 7: original identical + the 2 corrected-by-run-1 rows + the 3 created rows
      # (the blank enrollment compares nil==nil with forced-nil credits) + the ex-duplicate.
      assert_equal 7, counts[:identical]
      assert_equal 0, counts[:duplicate_cb]
      # manual + value->nil diffs persist as report-only every run:
      assert_equal 1, counts[:manual_diff]
      assert_equal 1, counts[:value_to_nil]
    ensure
      FileUtils.remove_entry(dir2)
    end
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `bin/rails test test/services/chulabooster/grade_sync_test.rb`
Expected: `3 runs, ... 0 failures, 0 errors`. If a count assertion fails, trace the actual bucket flow (the comments in the test derive each number) before touching the service — the dry-run and commit tests encode the spec's policy and are the ground truth.

- [ ] **Step 3: Commit**

```bash
hg add test/services/chulabooster/grade_sync_test.rb
hg commit test/services/chulabooster/grade_sync_test.rb -m "Test GradeSync bucket routing, correction gates, and ladder

Covers every row bucket (identical / value->value correction / nil->value fill / manual
protection / value->nil protection / sentinel / unknown student / CB-only create /
copied + placeholder ladder / duplicate CB row), the dry-run zero-writes invariant,
never-re-link, the blank-grade credits_grant nil rule, and commit idempotence."
```

---

### Task 7: Documentation + full-suite verification

**Files:**
- Modify: `CLAUDE.md` (ChulaBooster Integration section — after the "Student sync (Phase 2a)" bullet)

**Interfaces:**
- Consumes: everything above, complete and committed.

- [ ] **Step 1: Add the CLAUDE.md bullet**

After the Phase 2a bullet (ends with "Admin pointer page at `/chulabooster`."), add:

```markdown
- **Course + grade sync (Phase 2b)**: `bin/rails chulabooster:sync_courses` then
  `chulabooster:sync_grades` — same dry-run-default / `COMMIT=1` / `SNAPSHOT_DIR=` contract.
  Additive creates plus two audited correction classes: course placeholder-shell backfill and
  non-manual grade-value corrections (CB is registrar of record for grades; `manual` rows and
  CB-blank-vs-local-value are report-only). Grade identity is revision-insensitive
  (`student, course_no, year_ce, semester`) — full-key matching would duplicate
  revision-shadowed enrollments. New grades get `source: "chulabooster"`. Missing courses at
  grade time: exact → closest-revision copy → placeholder ladder. Design:
  `docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md`.
```

- [ ] **Step 2: Full suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors (baseline was 513 assertions-green before this plan; the suite has grown by Tasks 2, 5, 6).

- [ ] **Step 3: Re-verify both dry-runs one last time**

Run both snapshot dry-runs from Task 3 Step 4 and Task 4 Step 3 again; expected outputs unchanged. This catches anything the test tasks may have perturbed.

- [ ] **Step 4: Commit**

```bash
hg commit CLAUDE.md -m "Document Phase 2b course+grade sync in CLAUDE.md

Future sessions need the sync family's contract (dry-run default, COMMIT=1, SNAPSHOT_DIR),
the per-field authority policy, and the revision-insensitive grade identity without
re-reading the spec."
```

---

## Execution notes for the coordinating session

- Tasks 1–2 are independent of each other; 3 and 4 depend on nothing but Task 1 (GradeSync sets `source: "chulabooster"`). 5 depends on 3; 6 depends on 4 and the `@in_progress` fill path; 7 last.
- The two snapshot dry-runs (Tasks 3–4) each load the full dev DB into memory and take a few minutes — that is expected.
- **Reviewer gate on every commit: check `hg status` output against the task's file list before committing. Nothing outside the list goes in — especially not `config/credentials.yml.enc`.**
