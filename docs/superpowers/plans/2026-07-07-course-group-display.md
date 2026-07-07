# Course Group Display & Curriculum Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate `program_courses.course_group_code` (CB sync + legacy backfill) and surface curriculum groups on the program and course pages, with admin link management.

**Architecture:** A frozen label constant on `ProgramCourse` is the only lookup point for group names/order. A new `Chulabooster::ProgramCourseSync` (same dry-run/COMMIT contract as sibling syncs) fills tags from CB; a one-time `LegacyCourseGroupBackfill` parses the deprecated `courses.course_group` strings for gaps. The program show page gains a Curriculum card (grouped single table + Rooms-style Turbo Frame inline CRUD); the course show page gains per-program group badges; the destructive single-select on the course form becomes a multi-select.

**Tech Stack:** Rails 8.1, HAML, Turbo Frames, Select2 (Stimulus), Minitest + fixtures, Capybara system tests.

**Spec:** `docs/superpowers/specs/2026-07-06-course-group-display-design.md`

## Global Constraints

- **Version control is Mercurial (`hg`), not git.** Every commit MUST name its files explicitly (`hg commit path1 path2 -m "..."`) — the repo often has unrelated dirty changes. Use `hg add <file>` for new files first.
- **Commit messages lead with WHY** (first paragraph = problem/motivation), then what changed.
- **Testing is deferred to the final task** (project convention: tests are written once the feature is finished, and dae is asked first — see CLAUDE.md "Testing"). Tasks 1–9 verify via `bin/rails runner`, dry-run rake output, and rendered-page checks instead of per-task TDD. This deliberately overrides the default TDD step cycle.
- **No schema changes.** All data lands in existing columns (`program_courses.course_group_code`, `program_courses.course_type`). `courses.course_group` is deprecated but NOT dropped and its form field stays untouched.
- **Never overwrite a non-blank local `course_group_code`** — conflicts are report-only CSVs. Sync and backfill are additive (never delete links).
- **Existing links to the `0000` placeholder program are left alone** (report-only).
- All CSS/JS must stay intranet-local (no CDN). After SCSS edits run `bin/rails dartsass:build`.
- `AUTO_LOGIN=1` env var authenticates as user ID 1 (dev only) — used for page-render verification.
- Dev-DB facts for verification baselines: 553 `program_courses` rows (all `course_group_code` NULL), 257 courses with legacy `courses.course_group`, CB snapshot at `tmp/chulabooster_snapshot/20260706-041925/` has 172 `program_courses` rows (programs `4784` = CP 2566, `3736` = CP 2561; every `course_type` = 9).

---

### Task 1: Group label constant + helpers on ProgramCourse

**Files:**
- Modify: `app/models/program_course.rb` (currently 6 lines: belongs_to ×2 + uniqueness validation)

**Interfaces:**
- Produces: `ProgramCourse::COURSE_GROUP_LABELS` (frozen Hash, full code → label; **hash insertion order = display order**), `ProgramCourse::UNGROUPED_LABEL`, `ProgramCourse.group_label(code) → String`, `ProgramCourse.group_sort_key(code) → Array` (sortable; known codes by constant order, unknown codes alphabetically after, blank last), `ProgramCourse#group_label → String`.
- Consumes: nothing.

- [ ] **Step 1: Replace `app/models/program_course.rb` with:**

```ruby
class ProgramCourse < ApplicationRecord
  belongs_to :program
  belongs_to :course

  # Curriculum group labels, keyed by FULL course_group_code — per-program mapping,
  # so "4784-C" and "3736-C" are separate entries by design (programs may disagree
  # on a suffix's meaning). See docs/superpowers/specs/2026-07-06-course-group-display-design.md.
  #
  # HASH INSERTION ORDER = DISPLAY ORDER of groups on the program curriculum page.
  #
  # Entries whose label equals the raw suffix (e.g. "MS") mean the university's
  # meaning is unconfirmed — the raw suffix is shown until a real name is supplied.
  # Unknown codes not listed here render as their raw suffix automatically (see
  # .group_label), so new CB data never breaks the page.
  COURSE_GROUP_LABELS = {
    # CP 2566 curriculum (program_code 4784)
    "4784-C"     => "Compulsory",
    "4784-ELEC"  => "Elective",
    "4784-MS"    => "MS",
    "4784-ENG"   => "English",
    "4784-GLANG" => "GLANG",
    "4784-GSP"   => "GSP",
    "4784-SP"    => "SP",
    "4784-21"    => "21",
    # CP 2561 curriculum (program_code 3736)
    "3736-C"     => "Compulsory",
    "3736-ELEC"  => "Elective",
    "3736-ELEC2" => "Elective 2",
    "3736-MS"    => "MS",
    "3736-LANG"  => "Language",
    "3736-GSP"   => "GSP"
  }.freeze

  UNGROUPED_LABEL = "Ungrouped".freeze

  validates :course_id, uniqueness: { scope: :program_id }

  # Display label for a raw group code: constant first, raw suffix (prefix stripped)
  # for unknown codes, UNGROUPED_LABEL for blank.
  def self.group_label(code)
    return UNGROUPED_LABEL if code.blank?
    COURSE_GROUP_LABELS[code] || code.to_s.sub(/\A\d{4}-/, "")
  end

  # Sort key for ordering groups on the curriculum page: known codes in constant
  # order, then unknown codes alphabetically, then blank (Ungrouped) last.
  def self.group_sort_key(code)
    return [2, ""] if code.blank?
    idx = COURSE_GROUP_LABELS.keys.index(code)
    idx ? [0, idx.to_s.rjust(4, "0")] : [1, code.to_s]
  end

  def group_label
    self.class.group_label(course_group_code)
  end
end
```

- [ ] **Step 2: Verify with a runner script**

Run:
```bash
cd /home/dae/cp-api && bin/rails runner '
raise "label" unless ProgramCourse.group_label("4784-C") == "Compulsory"
raise "fallback" unless ProgramCourse.group_label("9999-XYZ") == "XYZ"
raise "blank" unless ProgramCourse.group_label(nil) == "Ungrouped"
keys = ["4784-ELEC", nil, "9999-A", "4784-C"]
sorted = keys.sort_by { |k| ProgramCourse.group_sort_key(k) }
raise "order #{sorted.inspect}" unless sorted == ["4784-C", "4784-ELEC", "9999-A", nil]
puts "OK"
'
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
cd /home/dae/cp-api && hg commit app/models/program_course.rb -m "Add course-group label mapping to ProgramCourse

The program<->course join has carried course_group_code since the m2m
remodel, but raw codes like 4784-GLANG are unreadable on a page. A frozen
constant (repo convention for enum-like fields) maps full codes to labels;
per-program keying was chosen because programs may disagree on a suffix's
meaning. Hash order doubles as curriculum display order, unknown codes fall
back to their raw suffix so future CB data renders without code changes.

- COURSE_GROUP_LABELS + UNGROUPED_LABEL constants
- group_label / group_sort_key class helpers, #group_label instance helper"
```

---

### Task 2: Chulabooster::ProgramCourseSync + rake task

**Files:**
- Create: `app/services/chulabooster/program_course_sync.rb`
- Modify: `lib/tasks/chulabooster.rake` (append a task at the end, inside `namespace :chulabooster`)

**Interfaces:**
- Consumes: `Chulabooster::Client`/`SnapshotClient#each_row("program_courses")` yielding hashes with keys `"program_id"` (= local `program_code`), `"course_id"` (`"<CE year><course_no>"`), `"course_no"`, `"course_group_code"`, `"course_type"`; `Chulabooster::Convert.parse_course_id`, `Convert.int_or_nil`.
- Produces: `Chulabooster::ProgramCourseSync.new(client:, run_dir:, commit: false)#call → Hash` of counts (keys: `:cb_rows, :unresolved, :identical, :created/:creatable, :filled/:fillable, :tag_discrepancies, :errors`); CSVs `created_pairings.csv`, `filled_tags.csv`, `tag_discrepancies.csv`, `skipped_rows.csv` in `run_dir`.

- [ ] **Step 1: Create `app/services/chulabooster/program_course_sync.rb`:**

```ruby
require "csv"
require "fileutils"

module Chulabooster
  # Mirrors CB's `program_courses` export (curriculum membership + group tag) into the
  # local program<->course join. Additive and non-destructive, per pairing:
  #   missing locally            -> create with CB tag                 (COMMIT-gated)
  #   exists, local tag blank    -> fill course_group_code/course_type (COMMIT-gated)
  #   exists, tags equal         -> no-op
  #   exists, tags differ        -> report-only, never overwritten
  # Local-only pairings are never touched. Dry-run (default) computes everything,
  # writes CSVs only. Policy: docs/superpowers/specs/2026-07-06-course-group-display-design.md
  class ProgramCourseSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      programs = Program.all.index_by(&:program_code)
      courses  = Course.all.index_by { |c| [c.course_no.to_s, c.revision_year_be] }
      pairings = ProgramCourse.includes(:program, :course)
                              .index_by { |pc| [pc.program_id, pc.course_id] }
      counts = Hash.new(0)
      rows = { created: [], filled: [], disc: [], skipped: [] }

      @client.each_row("program_courses") do |row|
        counts[:cb_rows] += 1
        program = programs[row["program_id"].to_s]
        course  = courses[course_key(row)]
        if program.nil? || course.nil?
          counts[:unresolved] += 1
          rows[:skipped] << [row["program_id"], row["course_id"], row["course_no"],
                             program.nil? ? "program not found" : "course not found"]
          next
        end

        cb_tag = row["course_group_code"].to_s.presence
        pairing = pairings[[program.id, course.id]]
        if pairing.nil?
          create_pairing(program, course, cb_tag, row, counts, rows)
        elsif pairing.course_group_code.to_s == cb_tag.to_s
          counts[:identical] += 1
        elsif pairing.course_group_code.blank?
          fill_tag(pairing, cb_tag, row, counts, rows)
        else
          counts[:tag_discrepancies] += 1
          rows[:disc] << [program.program_code, course.course_no, course.revision_year_be,
                          pairing.course_group_code, cb_tag]
        end
      end

      write_csv("created_pairings.csv", %w[program_code course_no revision_year_be course_group_code], rows[:created])
      write_csv("filled_tags.csv", %w[program_code course_no revision_year_be course_group_code], rows[:filled])
      write_csv("tag_discrepancies.csv", %w[program_code course_no revision_year_be local cb], rows[:disc])
      write_csv("skipped_rows.csv", %w[cb_program_id cb_course_id cb_course_no reason], rows[:skipped])
      counts
    end

    private

    # CB rows carry both course_id ("<CE year><course_no>") and an explicit course_no;
    # prefer the explicit field, as Mappers::ProgramCourses does.
    def course_key(row)
      course_no, rev_be = Convert.parse_course_id(row["course_id"])
      course_no = row["course_no"].to_s if row["course_no"].present?
      [course_no, rev_be]
    end

    def create_pairing(program, course, cb_tag, row, counts, rows)
      pairing = ProgramCourse.new(program: program, course: course,
                                  course_group_code: cb_tag,
                                  course_type: Convert.int_or_nil(row["course_type"]))
      ok = @commit ? pairing.save : pairing.valid?
      unless ok
        counts[:errors] += 1
        rows[:skipped] << [program.program_code, row["course_id"], course.course_no,
                           pairing.errors.full_messages.join("; ")]
        return
      end
      counts[@commit ? :created : :creatable] += 1
      rows[:created] << [program.program_code, course.course_no, course.revision_year_be, cb_tag]
    end

    def fill_tag(pairing, cb_tag, row, counts, rows)
      rows[:filled] << [pairing.program.program_code, pairing.course.course_no,
                        pairing.course.revision_year_be, cb_tag]
      counts[@commit ? :filled : :fillable] += 1
      return unless @commit
      pairing.update!(course_group_code: cb_tag,
                      course_type: Convert.int_or_nil(row["course_type"]))
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

- [ ] **Step 2: Append the rake task inside `namespace :chulabooster` in `lib/tasks/chulabooster.rake`** (after the `sync_grades` task's `end`, before the namespace's final `end`):

```ruby
  desc "Link CB-only program<->course pairings + fill blank course_group_code tags from CB. " \
       "Run sync_courses first. DRY-RUN by default; COMMIT=1 to write. " \
       "SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_program_courses: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync_program_courses", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — pairings WILL be created/tagged" : "MODE: dry-run — no database writes"
    counts = Chulabooster::ProgramCourseSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "cb rows:                #{counts[:cb_rows]}"
    puts "unresolved (skipped):   #{counts[:unresolved]}   <- skipped_rows.csv"
    puts "identical:              #{counts[:identical]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "#{commit ? 'tags filled:           ' : 'tags fillable:         '} #{counts[commit ? :filled : :fillable]}"
    puts "tag discrepancies:      #{counts[:tag_discrepancies]}   <- review tag_discrepancies.csv"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
```

- [ ] **Step 3: Dry-run against the snapshot to verify**

Run:
```bash
cd /home/dae/cp-api && SNAPSHOT_DIR=tmp/chulabooster_snapshot/20260706-041925 bin/rails chulabooster:sync_program_courses
```
(Use the newest dir under `tmp/chulabooster_snapshot/` if a fresher one exists.)

Expected: `MODE: dry-run`, `cb rows: 172`, `creatable` + `tags fillable` summing to ≤ 172, `row errors: 0`. Inspect the CSVs it names; confirm the DB is untouched:

```bash
cd /home/dae/cp-api && bin/rails runner 'puts ProgramCourse.where.not(course_group_code: nil).count'
```
Expected: `0`

- [ ] **Step 4: Commit**

```bash
cd /home/dae/cp-api && hg add app/services/chulabooster/program_course_sync.rb && hg commit app/services/chulabooster/program_course_sync.rb lib/tasks/chulabooster.rake -m "Sync program<->course pairings and group tags from ChulaBooster

program_courses.course_group_code has been NULL since the m2m remodel
deferred its population, so curriculum groups (compulsory/elective/...)
could not be displayed anywhere. CB's program_courses export carries the
per-pairing tag and is the registrar's source for it.

- Chulabooster::ProgramCourseSync: additive pairing creation, fill-blank-only
  tagging, differing tags report-only (protects future manual edits), same
  dry-run/COMMIT=1/SNAPSHOT_DIR contract as the sibling syncs
- chulabooster:sync_program_courses rake task with per-bucket counts + CSVs"
```

---

### Task 3: Legacy backfill service + rake task

**Files:**
- Create: `app/services/legacy_course_group_backfill.rb`
- Create: `lib/tasks/program_courses.rake`

**Interfaces:**
- Consumes: `Course#course_group` legacy strings (`"<program_code>-<suffix>"`), `Program#program_code`, `ProgramCourse`.
- Produces: `LegacyCourseGroupBackfill.new(run_dir:, commit: false)#call → Hash` of counts (keys: `:legacy_rows, :unparseable, :identical, :created/:creatable, :filled/:fillable, :tag_discrepancies, :placeholder_links, :errors`); CSVs `created_pairings.csv`, `filled_tags.csv`, `tag_discrepancies.csv`, `skipped_rows.csv`, `placeholder_links.csv` in `run_dir`.

- [ ] **Step 1: Create `app/services/legacy_course_group_backfill.rb`:**

```ruby
require "csv"
require "fileutils"

# One-time backfill: parses the deprecated per-course `courses.course_group` string
# ("<program_code>-<suffix>", e.g. "3736-ELEC2") into the per-pairing
# program_courses.course_group_code. Run AFTER chulabooster:sync_program_courses so CB
# wins wherever both sources know the answer: fill-blank-only, differing tags are
# report-only. Existing links from these courses to the 0000 placeholder program are
# left alone and reported. Additive — never deletes links or overwrites tags.
# Policy: docs/superpowers/specs/2026-07-06-course-group-display-design.md
class LegacyCourseGroupBackfill
  PATTERN = /\A(\d{4})-(.+)\z/

  def initialize(run_dir:, commit: false)
    @run_dir = run_dir
    @commit = commit
    FileUtils.mkdir_p(@run_dir)
  end

  def call
    programs = Program.all.index_by(&:program_code)
    placeholder = Program.find_by(program_code: "0000")
    counts = Hash.new(0)
    rows = { created: [], filled: [], disc: [], skipped: [], placeholder: [] }

    Course.where.not(course_group: [nil, ""]).find_each do |course|
      counts[:legacy_rows] += 1
      legacy = course.course_group.to_s.strip
      m = PATTERN.match(legacy)
      program = m && programs[m[1]]
      if program.nil?
        counts[:unparseable] += 1
        rows[:skipped] << [course.course_no, course.revision_year_be, legacy,
                           m ? "unknown program code" : "unparseable format"]
        next
      end

      if placeholder && ProgramCourse.exists?(program: placeholder, course: course)
        counts[:placeholder_links] += 1
        rows[:placeholder] << [course.course_no, course.revision_year_be, legacy]
      end

      pairing = ProgramCourse.find_by(program: program, course: course)
      if pairing.nil?
        create_pairing(program, course, legacy, counts, rows)
      elsif pairing.course_group_code.to_s == legacy
        counts[:identical] += 1
      elsif pairing.course_group_code.blank?
        rows[:filled] << [program.program_code, course.course_no, course.revision_year_be, legacy]
        counts[@commit ? :filled : :fillable] += 1
        pairing.update!(course_group_code: legacy) if @commit
      else
        counts[:tag_discrepancies] += 1
        rows[:disc] << [program.program_code, course.course_no, course.revision_year_be,
                        pairing.course_group_code, legacy]
      end
    end

    write_csv("created_pairings.csv", %w[program_code course_no revision_year_be course_group_code], rows[:created])
    write_csv("filled_tags.csv", %w[program_code course_no revision_year_be course_group_code], rows[:filled])
    write_csv("tag_discrepancies.csv", %w[program_code course_no revision_year_be existing legacy], rows[:disc])
    write_csv("skipped_rows.csv", %w[course_no revision_year_be course_group reason], rows[:skipped])
    write_csv("placeholder_links.csv", %w[course_no revision_year_be course_group], rows[:placeholder])
    counts
  end

  private

  def create_pairing(program, course, legacy, counts, rows)
    pairing = ProgramCourse.new(program: program, course: course, course_group_code: legacy)
    ok = @commit ? pairing.save : pairing.valid?
    unless ok
      counts[:errors] += 1
      rows[:skipped] << [course.course_no, course.revision_year_be, legacy,
                         pairing.errors.full_messages.join("; ")]
      return
    end
    counts[@commit ? :created : :creatable] += 1
    rows[:created] << [program.program_code, course.course_no, course.revision_year_be, legacy]
  end

  def write_csv(name, header, data_rows)
    CSV.open(File.join(@run_dir, name), "w") do |csv|
      csv << header
      data_rows.each { |r| csv << r }
    end
  end
end
```

- [ ] **Step 2: Create `lib/tasks/program_courses.rake`:**

```ruby
namespace :program_courses do
  desc "One-time backfill of program_courses.course_group_code from the deprecated " \
       "courses.course_group string. Run chulabooster:sync_program_courses FIRST so CB wins " \
       "where both sources know the answer. DRY-RUN by default; COMMIT=1 to write."
  task backfill_legacy_groups: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "legacy_group_backfill", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — pairings WILL be created/tagged" : "MODE: dry-run — no database writes"
    counts = LegacyCourseGroupBackfill.new(run_dir: run_dir, commit: commit).call

    puts
    puts "legacy course rows:     #{counts[:legacy_rows]}"
    puts "unparseable (skipped):  #{counts[:unparseable]}   <- skipped_rows.csv"
    puts "identical:              #{counts[:identical]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "#{commit ? 'tags filled:           ' : 'tags fillable:         '} #{counts[commit ? :filled : :fillable]}"
    puts "tag discrepancies:      #{counts[:tag_discrepancies]}   <- review tag_discrepancies.csv"
    puts "placeholder links:      #{counts[:placeholder_links]}   <- placeholder_links.csv (left alone)"
    puts "row errors:             #{counts[:errors]}"
    puts "\n→ reports: #{run_dir}"
  end
end
```

- [ ] **Step 3: Dry-run to verify**

Run:
```bash
cd /home/dae/cp-api && bin/rails program_courses:backfill_legacy_groups
```
Expected: `MODE: dry-run`, `legacy course rows: 257`, `unparseable (skipped): 0` (all dev values match `NNNN-SUFFIX`; if a few skip, inspect `skipped_rows.csv` — the count just must equal what the CSV explains), `row errors: 0`. Confirm no writes:

```bash
cd /home/dae/cp-api && bin/rails runner 'puts ProgramCourse.where.not(course_group_code: nil).count'
```
Expected: `0`

- [ ] **Step 4: Commit**

```bash
cd /home/dae/cp-api && hg add app/services/legacy_course_group_backfill.rb lib/tasks/program_courses.rake && hg commit app/services/legacy_course_group_backfill.rb lib/tasks/program_courses.rake -m "Backfill per-pairing group tags from the deprecated courses.course_group

The legacy per-course course_group string ('3736-ELEC2') predates the m2m
remodel and cannot represent a course that sits in two programs with
different group types; it also left many pairings pointing at the 0000
placeholder program instead of the program named in its own tag. CB's
export only covers pairings CB knows, so this one-time backfill fills the
rest — after the CB sync, fill-blank-only, conflicts report-only.

- LegacyCourseGroupBackfill service (dry-run default, COMMIT=1, CSV reports)
- program_courses:backfill_legacy_groups rake task"
```

---

### Task 4: Populate the dev database

No code — runs the two tasks with `COMMIT=1` against the local dev DB so the UI tasks have real data to render. (Production runs are dae's call, after this feature ships — see Task 9.)

- [ ] **Step 1: CB sync, dry-run reviewed then committed**

```bash
cd /home/dae/cp-api && SNAPSHOT_DIR=tmp/chulabooster_snapshot/20260706-041925 bin/rails chulabooster:sync_program_courses
cd /home/dae/cp-api && SNAPSHOT_DIR=tmp/chulabooster_snapshot/20260706-041925 COMMIT=1 bin/rails chulabooster:sync_program_courses
```
Expected: COMMIT run reports `created:` + `tags filled:` matching the dry-run's `creatable`/`fillable`, `row errors: 0`.

- [ ] **Step 2: Legacy backfill, dry-run reviewed then committed**

```bash
cd /home/dae/cp-api && bin/rails program_courses:backfill_legacy_groups
cd /home/dae/cp-api && COMMIT=1 bin/rails program_courses:backfill_legacy_groups
```
Expected: `row errors: 0`; `tag discrepancies` may be non-zero (CB already tagged those pairings) — that is correct behavior, review the CSV.

- [ ] **Step 3: Verify populated tags**

```bash
cd /home/dae/cp-api && bin/rails runner '
tagged = ProgramCourse.where.not(course_group_code: [nil, ""])
puts "tagged pairings: #{tagged.count}"
tagged.group(:course_group_code).count.sort.each { |k, v| puts "  #{k}: #{v}" }
'
```
Expected: `tagged pairings:` > 200; codes limited to the `4784-*`/`3736-*` families. Re-run either task a second time — every bucket except `identical` must be 0 (idempotence).

---

### Task 5: Curriculum card on the program show page (read-only)

**Files:**
- Modify: `app/controllers/programs_controller.rb` (`show`, lines 11–15)
- Modify: `app/views/programs/show.html.haml` (insert card after the detail card, i.e. between the `.card` that ends with `Updated at` and `- if @students.any?`)

**Interfaces:**
- Consumes: `ProgramCourse.group_sort_key`, `ProgramCourse.group_label` (Task 1); populated `course_group_code` (Task 4).
- Produces: `@curriculum` — `Hash{String|nil => Array<ProgramCourse>}` in display order, consumed by the view (and extended in Task 6).

- [ ] **Step 1: Load grouped curriculum in `ProgramsController#show`.** Replace the `show` method with:

```ruby
  def show
    @students = @program.students.order(admission_year_be: :desc, student_id: :asc)
    @curriculum = @program.program_courses.includes(:course)
                          .sort_by { |pc| [ProgramCourse.group_sort_key(pc.course_group_code), pc.course.course_no] }
                          .group_by(&:course_group_code)
    prepare_admission_chart_data(@students)
    prepare_gpa_chart_data([@program.id])
  end
```

- [ ] **Step 2: Insert the Curriculum card** in `app/views/programs/show.html.haml`, directly after the detail `.card` block (the one whose last lines render `Updated at`) and before `- if @students.any?`:

```haml
.card.mt-3
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon("courses")
        Curriculum
        %span.text-muted.ms-2.fw-normal
          (#{@curriculum.values.sum(&:size)})

    - if @curriculum.any?
      .table-responsive
        %table.table.table-hover.mb-0
          %thead
            %tr
              %th Course No
              %th Name
              %th.text-center Credits
              %th Actions
          %tbody
            - @curriculum.each_with_index do |(code, pairings), idx|
              - if idx.positive?
                %tr.table-group-spacer{"aria-hidden" => "true"}
                  %td{colspan: 4}
              %tr.table-group-header
                %td{colspan: 4}
                  %strong= ProgramCourse.group_label(code)
                  - if code.present?
                    %span.text-muted.ms-2.fw-normal= code
                  %span.text-muted.ms-2.fw-normal
                    (#{pairings.size})
              - pairings.each do |pc|
                %tr
                  %td= link_to pc.course.course_no, pc.course
                  %td= pc.course.name
                  %td.text-center= pc.course.credits
                  %td
                    = link_to pc.course, class: "btn-ghost btn-ghost-primary", title: "Show" do
                      %span.material-symbols{style: "font-size: 18px"} visibility
    - else
      %p.text-muted.mb-0 No courses linked to this program.
```

Deliberately **no** `data-controller: datatable` on this card — DataTables' client-side sorting would tear the group-header rows apart (same reason the students/show grade tables don't use it).

- [ ] **Step 3: Verify the rendered page**

```bash
cd /home/dae/cp-api && bin/rails runner 'puts Program.find_by(program_code: "4784").id' 
cd /home/dae/cp-api && AUTO_LOGIN=1 bin/rails server -p 3001 -d
sleep 3 && curl -s http://localhost:3001/programs/<ID-from-above> -o /tmp/prog.html
grep -c "table-group-header" /tmp/prog.html && grep -o "Compulsory\|Elective\|Curriculum" /tmp/prog.html | sort | uniq -c
kill $(cat /home/dae/cp-api/tmp/pids/server.pid)
```
Expected: `table-group-header` count ≥ 2; `Curriculum`, `Compulsory`, `Elective` all present. Also spot-check a program with no courses (e.g. `Program.find_by(program_code: "0000")` excluded — pick any master's program) renders "No courses linked to this program."

- [ ] **Step 4: Commit**

```bash
cd /home/dae/cp-api && hg commit app/controllers/programs_controller.rb app/views/programs/show.html.haml -m "Show the curriculum, grouped by course group, on the program page

Course-group tags are now populated on the program<->course join, but no
page displayed them — you could not answer 'which courses are compulsory
in this program?' anywhere in the app.

- ProgramsController#show builds @curriculum ordered by the label
  constant's display order (unknown codes after, Ungrouped last)
- Curriculum card: single table with .table-group-header/.table-group-spacer
  rows per group; no DataTable (sorting would tear the group rows apart)"
```

---

### Task 6: Admin link management from the program page

**Files:**
- Modify: `config/routes.rb` (line with bare `resources :programs`)
- Create: `app/controllers/program_courses_controller.rb`
- Create: `app/helpers/program_courses_helper.rb`
- Create: `app/views/program_courses/new.html.haml`
- Create: `app/views/program_courses/edit.html.haml`
- Create: `app/views/program_courses/_form.html.haml`
- Modify: `app/views/programs/show.html.haml` (Curriculum card from Task 5: add frame + admin buttons)

**Interfaces:**
- Consumes: `@curriculum` view structure (Task 5), `ProgramCourse` validations (Task 1), Rooms Turbo-Frame pattern.
- Produces: routes `new_program_program_course_path(program)`, `edit_program_program_course_path(program, pc)`, `program_program_course_path(program, pc)`; helpers `available_courses(program)`, `group_code_suggestions(program)`.

- [ ] **Step 1: Nest the routes.** In `config/routes.rb`, replace the line `resources :programs` with:

```ruby
  resources :programs do
    resources :program_courses, only: %i[new create edit update destroy]
  end
```

- [ ] **Step 2: Create `app/controllers/program_courses_controller.rb`:**

```ruby
class ProgramCoursesController < ApplicationController
  before_action :require_admin
  before_action :set_program
  before_action :set_program_course, only: %i[edit update destroy]

  def new
    @program_course = @program.program_courses.new
  end

  def create
    @program_course = @program.program_courses.new(create_params)
    if @program_course.save
      redirect_to @program, notice: "Course was added to the program."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @program_course.update(update_params)
      redirect_to @program, notice: "Course group was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @program_course.destroy!
    redirect_to @program, notice: "Course was removed from the program."
  end

  private

  def set_program
    @program = Program.find(params[:program_id])
  end

  def set_program_course
    @program_course = @program.program_courses.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to programs_path, alert: "Only admins can perform this action."
    end
  end

  def create_params
    params.require(:program_course).permit(:course_id, :course_group_code)
  end

  # The linked course is immutable once created — editing only changes the tag.
  # (To move a link to another course: remove + re-add.)
  def update_params
    params.require(:program_course).permit(:course_group_code)
  end
end
```

- [ ] **Step 3: Create `app/helpers/program_courses_helper.rb`:**

```ruby
module ProgramCoursesHelper
  # Courses not yet linked to this program, for the "Add Course" dropdown.
  def available_courses(program)
    Course.where.not(id: program.course_ids).order(:course_no, revision_year_be: :desc)
  end

  # Datalist suggestions for the group-code field: codes already used by this
  # program + label-constant keys carrying this program's prefix.
  def group_code_suggestions(program)
    used = program.program_courses.where.not(course_group_code: [nil, ""])
                  .distinct.pluck(:course_group_code)
    known = ProgramCourse::COURSE_GROUP_LABELS.keys
                                              .select { |k| k.start_with?("#{program.program_code}-") }
    (used + known).uniq.sort
  end
end
```

- [ ] **Step 4: Create `app/views/program_courses/new.html.haml`:**

```haml
= turbo_frame_tag "program_course_form" do
  .card.mb-3.border-primary
    .card-body.py-2.px-3
      %h6.card-title.mb-2 Add Course
      = render "form", program: @program, program_course: @program_course
```

- [ ] **Step 5: Create `app/views/program_courses/edit.html.haml`:**

```haml
= turbo_frame_tag "program_course_form" do
  .card.mb-3.border-primary
    .card-body.py-2.px-3
      %h6.card-title.mb-2 Edit Course Group
      = render "form", program: @program, program_course: @program_course
```

- [ ] **Step 6: Create `app/views/program_courses/_form.html.haml`:**

```haml
= form_with(model: [program, program_course], data: { turbo_frame: "_top" }) do |f|
  - if program_course.errors.any?
    .alert.alert-danger.py-2.px-3.mb-2
      %ul.mb-0.small
        - program_course.errors.full_messages.each do |message|
          %li= message

  .row.g-2.align-items-end
    .col-md-6
      = f.label :course_id, "Course", class: "form-label small text-muted mb-0"
      - if program_course.persisted?
        %input.form-control.form-control-sm{type: "text", disabled: true,
          value: "#{program_course.course.course_no} — #{program_course.course.name} (#{program_course.course.revision_year_be})"}
      - else
        = f.select :course_id,
          options_for_select(available_courses(program).map { |c| ["#{c.course_no} — #{c.name} (#{c.revision_year_be})", c.id] }, program_course.course_id),
          { include_blank: "Select a course" },
          class: "form-select form-select-sm", data: { controller: "select2" }
    .col-md-3
      = f.label :course_group_code, "Group Code", class: "form-label small text-muted mb-0"
      = f.text_field :course_group_code, class: "form-control form-control-sm",
        list: "course-group-codes", placeholder: "e.g. #{program.program_code}-C"
      %datalist#course-group-codes
        - group_code_suggestions(program).each do |code|
          %option{value: code}
    .col-md-3
      .d-flex.gap-2
        = f.submit (program_course.persisted? ? "Save" : "Add Course"), class: "btn btn-primary btn-sm"
        = link_to "Cancel", program_path(program), class: "btn btn-outline-secondary btn-sm"
```

- [ ] **Step 7: Wire the Curriculum card.** In `app/views/programs/show.html.haml` (card from Task 5):

Add the admin button inside the title row's flex container (after the `%h5.card-title` block, as its sibling):

```haml
      - if current_user.admin?
        = link_to new_program_program_course_path(@program), class: "btn btn-primary btn-sm", data: { turbo_frame: "program_course_form" } do
          %span.material-symbols.me-1{style: "font-size: 16px; vertical-align: middle"} add
          Add Course
```

Add the frame placeholder directly under the title row (before `- if @curriculum.any?`):

```haml
    = turbo_frame_tag "program_course_form"
```

Replace the per-row Actions cell (the `%td` containing the visibility link) with:

```haml
                  %td
                    = link_to pc.course, class: "btn-ghost btn-ghost-primary me-1", title: "Show" do
                      %span.material-symbols{style: "font-size: 18px"} visibility
                    - if current_user.admin?
                      = link_to edit_program_program_course_path(@program, pc), class: "btn-ghost btn-ghost-secondary me-1", title: "Edit", data: { turbo_frame: "program_course_form" } do
                        %span.material-symbols{style: "font-size: 18px"} edit
                      = link_to program_program_course_path(@program, pc), data: { turbo_method: :delete, turbo_confirm: "Remove #{pc.course.course_no} from this program?" }, class: "btn-ghost btn-ghost-danger", title: "Remove" do
                        %span.material-symbols{style: "font-size: 18px"} delete
```

- [ ] **Step 8: Verify routes and forms render**

```bash
cd /home/dae/cp-api && bin/rails routes -g program_courses
```
Expected: 5 routes (new/create/edit/update/destroy) nested under `/programs/:program_id/`.

```bash
cd /home/dae/cp-api && AUTO_LOGIN=1 bin/rails server -p 3001 -d
sleep 3
ID=$(bin/rails runner 'print Program.find_by(program_code: "4784").id')
curl -s "http://localhost:3001/programs/$ID/program_courses/new" | grep -c "program_course_form"
PC=$(bin/rails runner 'print Program.find_by(program_code: "4784").program_courses.first.id')
curl -s "http://localhost:3001/programs/$ID/program_courses/$PC/edit" | grep -c "Edit Course Group"
curl -s "http://localhost:3001/programs/$ID" | grep -c "Add Course"
kill $(cat /home/dae/cp-api/tmp/pids/server.pid)
```
Expected: each grep count ≥ 1. (Full click-through add/edit/remove flow is covered by the Task 10 system tests; a manual browser pass with `AUTO_LOGIN=1 bin/dev` is optional here.)

- [ ] **Step 9: Commit**

```bash
cd /home/dae/cp-api && hg add app/controllers/program_courses_controller.rb app/helpers/program_courses_helper.rb app/views/program_courses/new.html.haml app/views/program_courses/edit.html.haml app/views/program_courses/_form.html.haml && hg commit config/routes.rb app/controllers/program_courses_controller.rb app/helpers/program_courses_helper.rb app/views/program_courses/new.html.haml app/views/program_courses/edit.html.haml app/views/program_courses/_form.html.haml app/views/programs/show.html.haml -m "Manage program<->course links from the program page

Until now the m2m had no real maintenance path: the only UI was the course
form's single-select, which silently deletes all other program links on
save, and nothing anywhere could set a pairing's group tag.

- Nested ProgramCoursesController (admin-only), Rooms-style Turbo Frame
  inline forms on the Curriculum card
- Add form: courses not yet linked + group-code field with datalist
  suggestions; edit form changes only the tag; remove deletes the link only"
```

---

### Task 7: Group badges on the course page + badge SCSS

**Files:**
- Modify: `app/controllers/courses_controller.rb` (`show`)
- Modify: `app/views/courses/show.html.haml` (Program `dd` block ~lines 31–38; legacy Course Group row ~lines 43–45)
- Modify: `app/assets/stylesheets/application.scss` (badge block, after `.badge-chulabooster`)
- Modify: `CLAUDE.md` (badge class list)

**Interfaces:**
- Consumes: `ProgramCourse#group_label` (Task 1).
- Produces: `@program_pairings` in `CoursesController#show`; `.badge-course-group` SCSS class.

- [ ] **Step 1: Load pairings in `CoursesController#show`.** Add this line at the top of the `show` method body:

```ruby
    @program_pairings = @course.program_courses.includes(program: :program_group)
```

- [ ] **Step 2: Replace the Program `dd` block** in `app/views/courses/show.html.haml` (currently iterating `@course.programs`):

```haml
            %dt.col-sm-4 Program
            %dd.col-sm-8
              - if @program_pairings.any?
                - @program_pairings.each do |pc|
                  .mb-1
                    = link_to pc.program.name_en, pc.program
                    - if pc.course_group_code.present?
                      %span.badge.badge-course-group.ms-2{title: pc.course_group_code}= pc.group_label
              - else
                .text-muted Not assigned
```

- [ ] **Step 3: Delete the legacy Course Group row** from the same file (the three lines rendering `@course.course_group` behind an `if present?`) — the information now appears per pairing. (`courses.course_group` itself stays in the DB and in the course form; the students/show Course History table also still reads it — both are follow-ups for the eventual column drop, out of scope here.)

- [ ] **Step 4: Add the badge class** in `app/assets/stylesheets/application.scss`, on a new line directly after `.badge-chulabooster { ... }`:

```scss
// Curriculum group tag on a program<->course pairing (Compulsory/Elective/...).
.badge-course-group { background-color: rgba($info, 0.12);             color: $info;    border: 1px solid rgba($info, 0.3); }
```

(Same hue family as `.badge-chulabooster` at lower alpha — different domain concept sharing a similar color is allowed per CLAUDE.md.)

- [ ] **Step 5: Add `.badge-course-group` to the CLAUDE.md badge list** — in the `**Badges**` bullet, append `, .badge-course-group` after `.badge-chulabooster` in the "Existing classes:" enumeration.

- [ ] **Step 6: Rebuild CSS and verify**

```bash
cd /home/dae/cp-api && bin/rails dartsass:build && grep -c "badge-course-group" app/assets/builds/application.css
```
Expected: build succeeds, grep ≥ 1.

```bash
cd /home/dae/cp-api && AUTO_LOGIN=1 bin/rails server -p 3001 -d
sleep 3
CID=$(bin/rails runner 'print ProgramCourse.where.not(course_group_code: [nil, ""]).first.course_id')
curl -s "http://localhost:3001/courses/$CID" | grep -c "badge-course-group"
kill $(cat /home/dae/cp-api/tmp/pids/server.pid)
```
Expected: ≥ 1.

- [ ] **Step 7: Commit**

```bash
cd /home/dae/cp-api && hg commit app/controllers/courses_controller.rb app/views/courses/show.html.haml app/assets/stylesheets/application.scss CLAUDE.md -m "Show per-program group badges on the course page

The course page showed the deprecated per-course course_group string,
which cannot express that a course is compulsory in one program and
elective in another; the real per-pairing tags were invisible.

- Programs list renders each pairing's group label as .badge-course-group
  (raw code in the title attribute), legacy Course Group row removed
- New badge class registered in CLAUDE.md's badge list"
```

---

### Task 8: Fix the destructive program select on the course form

**Files:**
- Modify: `app/views/courses/_form.html.haml` (the `course[program_id]` select, ~line 59)
- Modify: `app/controllers/courses_controller.rb` (`program_ids_param`, bottom of file)

**Interfaces:**
- Consumes: existing `@course.program_ids = program_ids_param` assignments in `create`/`update` (unchanged).
- Produces: form field named `course[program_ids][]`.

- [ ] **Step 1: Replace the single select with a multi-select.** In `app/views/courses/_form.html.haml`, replace the two lines (`f.label :program_id ...` and `select_tag "course[program_id]" ...`) with:

```haml
        = f.label :program_ids, "Programs", class: "form-label"
        = select_tag "course[program_ids][]", options_for_select(Program.includes(:program_group).order(year_started_be: :desc).map { |p| ["#{p.program_group.code} — #{p.program_code} — #{p.name_en} (#{p.year_started_be})", p.id] }, course.program_ids), multiple: true, class: "form-select", data: { controller: "select2" }
```

Leave the neighboring legacy `course_group` text field untouched (deprecated column, removed together with the column later).

- [ ] **Step 2: Accept the array param.** In `app/controllers/courses_controller.rb`, replace `program_ids_param` with:

```ruby
  def program_ids_param
    Array(params.dig(:course, :program_ids)).compact_blank
  end
```

Note the semantics this fixes: previously, editing a course linked to programs A and B showed only A and saving deleted the B link silently. Now all links are visible and preserved; `program_ids=` keeps the join rows (and their group tags) for programs that remain selected. Deselecting everything now explicitly unlinks all programs — visible in the UI, unlike before.

- [ ] **Step 3: Verify tag survival through a form-equivalent update**

```bash
cd /home/dae/cp-api && bin/rails runner '
pc = ProgramCourse.where.not(course_group_code: [nil, ""]).first
course, tag = pc.course, pc.course_group_code
course.program_ids = course.program_ids  # what update does when selection unchanged
course.save!
raise "tag lost!" unless pc.reload.course_group_code == tag
puts "OK — tag survives"
'
```
Expected: `OK — tag survives`

Then render the edit form:
```bash
cd /home/dae/cp-api && AUTO_LOGIN=1 bin/rails server -p 3001 -d
sleep 3
CID=$(bin/rails runner 'print ProgramCourse.where.not(course_group_code: [nil, ""]).first.course_id')
curl -s "http://localhost:3001/courses/$CID/edit" | grep -c 'course\[program_ids\]\[\]'
kill $(cat /home/dae/cp-api/tmp/pids/server.pid)
```
Expected: ≥ 1.

- [ ] **Step 4: Commit**

```bash
cd /home/dae/cp-api && hg commit app/views/courses/_form.html.haml app/controllers/courses_controller.rb -m "Stop the course form from silently deleting program links

The form rendered a single-select of course.programs.first and saved via
program_ids = [that one], so editing any course linked to two programs
silently dropped the second link — and with group tags now populated,
their tags with it.

- Program select becomes a Select2 multi-select prefilled with all linked
  programs; controller accepts course[program_ids][]
- Kept selections keep their join rows, so group tags survive edits"
```

---

### Task 9: Documentation + production-run note

**Files:**
- Modify: `CLAUDE.md` (Data Model Conventions section + ChulaBooster Integration section)

**Interfaces:** none (docs only).

- [ ] **Step 1: Add a bullet to CLAUDE.md's "Data Model Conventions"** (after the Course `course_no` bullet):

```markdown
- **Course groups are per-pairing**: `program_courses.course_group_code` (raw university code, e.g. `"4784-C"` = `<program_code>-<suffix>`) tags each program↔course pairing with its curriculum group. Labels + display order come from `ProgramCourse::COURSE_GROUP_LABELS` (frozen, full-code keys; unknown codes render as their raw suffix). Populated by `chulabooster:sync_program_courses` (fill-blank-only, conflicts report-only) + one-time `program_courses:backfill_legacy_groups`. `courses.course_group` is **deprecated** (still read by students/show Course History; drop both together later). Managed in the UI from the program page's Curriculum card.
```

- [ ] **Step 2: Add the sync to CLAUDE.md's ChulaBooster section** — in the "Course + grade sync (Phase 2b)" bullet's neighborhood, append a sentence to the section intro or the 2b bullet:

```markdown
- **Program-course sync**: `bin/rails chulabooster:sync_program_courses` — links CB-only
  pairings and fills blank `course_group_code` tags (same dry-run/`COMMIT=1`/`SNAPSHOT_DIR=`
  contract; differing tags report-only). Run `program_courses:backfill_legacy_groups` after
  it, once, to fill what CB doesn't cover.
```

- [ ] **Step 3: Commit**

```bash
cd /home/dae/cp-api && hg commit CLAUDE.md -m "Document course-group conventions and the program-course sync

Course-group tags now live on the m2m join with a label constant, a CB
sync, and a legacy backfill — future work needs to know the column is
per-pairing, that courses.course_group is deprecated, and which task
populates what."
```

- [ ] **Step 4: Note for dae (not a code step):** production runs are your call once the feature is reviewed — `chulabooster:sync_program_courses` (dry-run first), then `program_courses:backfill_legacy_groups` (dry-run first), mirroring the dev sequence from Task 4.

---

### Task 10: Test suite (GATED — ask dae first)

**Files:**
- Modify: `test/fixtures/program_courses.yml`
- Create: `test/models/program_course_test.rb`
- Create: `test/services/chulabooster/program_course_sync_test.rb`
- Create: `test/services/legacy_course_group_backfill_test.rb`
- Create: `test/system/program_curriculum_test.rb`
- Modify: `test/system/courses_test.rb` (add one regression test)

**Interfaces:**
- Consumes: everything above; fixtures `programs(:cp_bachelor)` (program_code `"2101"`), `courses(:intro_computing, :senior_project, :gened_course)`, `users(:admin, :viewer)`; system-test login = visit `login_path`, fill Username/Password (`password123`), click "Sign In" (see `test/system/rooms_test.rb`).

- [ ] **Step 1: Ask dae before writing anything** (CLAUDE.md requires discussing test scope first):

> "Feature complete. Planned tests: (a) model — group_label/group_sort_key; (b) service — ProgramCourseSync buckets (create/fill/identical/conflict-report/unresolved-skip, dry-run writes nothing); (c) service — LegacyCourseGroupBackfill (parse, correct-program pairing creation, fill-blank-only, conflict report, placeholder link untouched); (d) system — curriculum card grouping/ordering + admin add/edit/remove + viewer sees no controls; (e) system regression — editing a two-program course through the course form keeps both links. Proceed / trim?"

**STOP until dae answers.** Apply any trims, then continue.

- [ ] **Step 2: Tag fixtures.** In `test/fixtures/program_courses.yml`, replace the file contents with:

```yaml
intro_cp:
  program: cp_bachelor
  course: intro_computing
  course_group_code: 2101-C

senior_cp:
  program: cp_bachelor
  course: senior_project
  course_group_code: 2101-ELEC

gened_cp:
  program: cp_bachelor
  course: gened_course
```

- [ ] **Step 3: Create `test/models/program_course_test.rb`:**

```ruby
require "test_helper"

class ProgramCourseTest < ActiveSupport::TestCase
  test "group_label maps known codes via the constant" do
    assert_equal "Compulsory", ProgramCourse.group_label("4784-C")
  end

  test "group_label falls back to the raw suffix for unknown codes" do
    assert_equal "NEWGRP", ProgramCourse.group_label("9999-NEWGRP")
  end

  test "group_label handles blank" do
    assert_equal ProgramCourse::UNGROUPED_LABEL, ProgramCourse.group_label(nil)
    assert_equal ProgramCourse::UNGROUPED_LABEL, ProgramCourse.group_label("")
  end

  test "group_sort_key orders: constant order, unknown alphabetical, blank last" do
    codes = [nil, "9999-B", "4784-ELEC", "9999-A", "4784-C"]
    sorted = codes.sort_by { |c| ProgramCourse.group_sort_key(c) }
    assert_equal ["4784-C", "4784-ELEC", "9999-A", "9999-B", nil], sorted
  end

  test "course is unique per program" do
    dup = ProgramCourse.new(program: programs(:cp_bachelor), course: courses(:intro_computing))
    assert_not dup.valid?
  end
end
```

- [ ] **Step 4: Run model tests**

Run: `cd /home/dae/cp-api && bin/rails test test/models/program_course_test.rb`
Expected: `0 failures, 0 errors`

- [ ] **Step 5: Create `test/services/chulabooster/program_course_sync_test.rb`:**

```ruby
require "test_helper"
require "tmpdir"
require "csv"

class Chulabooster::ProgramCourseSyncTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(rows) = @rows = rows
    def each_row(_entity)
      @rows.each { |r| yield r }
    end
  end

  setup do
    @dir = Dir.mktmpdir("pc-sync-test")
    @program = programs(:cp_bachelor)          # program_code "2101"
    @linked_blank = program_courses(:gened_cp) # pairing exists, no tag
    @linked_tagged = program_courses(:intro_cp) # pairing exists, tag "2101-C"
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  # CB row builder. course_id = "<CE year><course_no>".
  def cb_row(course, tag, program_code: "2101")
    { "program_id"        => program_code,
      "course_id"         => "#{course.revision_year_be - 543}#{course.course_no}",
      "course_no"         => course.course_no,
      "course_group_code" => tag,
      "course_type"       => 9 }
  end

  def run_sync(rows, commit: false)
    Chulabooster::ProgramCourseSync.new(client: FakeClient.new(rows), run_dir: @dir,
                                        commit: commit).call
  end

  test "creates a missing pairing with the CB tag on commit" do
    course = Course.create!(course_no: "2110999", revision_year_be: 2565, name: "New")
    counts = run_sync([cb_row(course, "2101-C")], commit: true)
    assert_equal 1, counts[:created]
    assert_equal "2101-C", ProgramCourse.find_by(program: @program, course: course).course_group_code
  end

  test "fills a blank tag, mirrors course_type" do
    counts = run_sync([cb_row(@linked_blank.course, "2101-GSP")], commit: true)
    assert_equal 1, counts[:filled]
    @linked_blank.reload
    assert_equal "2101-GSP", @linked_blank.course_group_code
    assert_equal 9, @linked_blank.course_type
  end

  test "never overwrites a differing tag — reports it" do
    counts = run_sync([cb_row(@linked_tagged.course, "2101-DIFFERENT")], commit: true)
    assert_equal 1, counts[:tag_discrepancies]
    assert_equal "2101-C", @linked_tagged.reload.course_group_code
    disc = CSV.read(File.join(@dir, "tag_discrepancies.csv"), headers: true)
    assert_equal "2101-DIFFERENT", disc.first["cb"]
  end

  test "identical tag is a no-op" do
    counts = run_sync([cb_row(@linked_tagged.course, "2101-C")], commit: true)
    assert_equal 1, counts[:identical]
    assert_equal 0, counts[:filled] + counts[:created] + counts[:tag_discrepancies]
  end

  test "unresolvable program or course is skipped and reported" do
    ghost = cb_row(courses(:intro_computing), "9999-C", program_code: "9999")
    counts = run_sync([ghost], commit: true)
    assert_equal 1, counts[:unresolved]
    skipped = CSV.read(File.join(@dir, "skipped_rows.csv"), headers: true)
    assert_equal "program not found", skipped.first["reason"]
  end

  test "dry-run writes nothing" do
    course = Course.create!(course_no: "2110998", revision_year_be: 2565, name: "New2")
    counts = run_sync([cb_row(course, "2101-C"), cb_row(@linked_blank.course, "2101-GSP")])
    assert_equal 1, counts[:creatable]
    assert_equal 1, counts[:fillable]
    assert_nil ProgramCourse.find_by(program: @program, course: course)
    assert_nil @linked_blank.reload.course_group_code
  end
end
```

- [ ] **Step 6: Create `test/services/legacy_course_group_backfill_test.rb`:**

```ruby
require "test_helper"
require "tmpdir"
require "csv"

class LegacyCourseGroupBackfillTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("legacy-backfill-test")
    @program = programs(:cp_bachelor) # program_code "2101"
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  def run_backfill(commit: true)
    LegacyCourseGroupBackfill.new(run_dir: @dir, commit: commit).call
  end

  test "creates the pairing named by the legacy prefix" do
    course = Course.create!(course_no: "2110997", revision_year_be: 2565, name: "Legacy",
                            course_group: "2101-MS")
    counts = run_backfill
    assert_equal 1, counts[:created]
    assert_equal "2101-MS",
                 ProgramCourse.find_by(program: @program, course: course).course_group_code
  end

  test "fills a blank tag on an existing pairing" do
    pc = program_courses(:gened_cp)
    pc.course.update!(course_group: "2101-GENED")
    counts = run_backfill
    assert_equal 1, counts[:filled]
    assert_equal "2101-GENED", pc.reload.course_group_code
  end

  test "never overwrites an existing differing tag" do
    pc = program_courses(:intro_cp) # tag "2101-C"
    pc.course.update!(course_group: "2101-OTHER")
    counts = run_backfill
    assert_equal 1, counts[:tag_discrepancies]
    assert_equal "2101-C", pc.reload.course_group_code
  end

  test "skips and reports unparseable values and unknown program codes" do
    Course.create!(course_no: "2110996", revision_year_be: 2565, name: "Bad1",
                   course_group: "Project")
    Course.create!(course_no: "2110995", revision_year_be: 2565, name: "Bad2",
                   course_group: "9999-C")
    counts = run_backfill
    # 3, not 2: the senior_project fixture ships legacy course_group "Project",
    # which every run_backfill in this file also processes (unparseable).
    assert_equal 3, counts[:unparseable]
    reasons = CSV.read(File.join(@dir, "skipped_rows.csv"), headers: true).map { |r| r["reason"] }
    assert_includes reasons, "unparseable format"
    assert_includes reasons, "unknown program code"
  end

  test "leaves placeholder-program links alone and reports them" do
    placeholder = Program.placeholder
    course = Course.create!(course_no: "2110994", revision_year_be: 2565, name: "Ph",
                            course_group: "2101-C")
    ProgramCourse.create!(program: placeholder, course: course)
    counts = run_backfill
    assert_equal 1, counts[:placeholder_links]
    assert ProgramCourse.exists?(program: placeholder, course: course), "placeholder link deleted"
    assert ProgramCourse.exists?(program: @program, course: course), "correct pairing not created"
  end

  test "dry-run writes nothing" do
    course = Course.create!(course_no: "2110993", revision_year_be: 2565, name: "Dry",
                            course_group: "2101-C")
    counts = run_backfill(commit: false)
    assert_equal 1, counts[:creatable]
    assert_nil ProgramCourse.find_by(program: @program, course: course)
  end
end
```

Note: `Program.placeholder` creates the `0000` program under the `OTHER` group; if the fixtures lack an `OTHER` program group, add to `test/fixtures/program_groups.yml`:

```yaml
other_group:
  code: OTHER
  name_en: Other
  degree_level: bachelor
  degree_name: Placeholder
```

(Check the existing fixture file first — only add if absent, matching its column set.)

- [ ] **Step 7: Run service tests**

Run: `cd /home/dae/cp-api && bin/rails test test/services/chulabooster/program_course_sync_test.rb test/services/legacy_course_group_backfill_test.rb`
Expected: `0 failures, 0 errors`

- [ ] **Step 8: Create `test/system/program_curriculum_test.rb`:**

```ruby
require "application_system_test_case"

class ProgramCurriculumTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "curriculum shows courses grouped by group label, constant order, ungrouped last" do
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))

    assert_text "Curriculum"
    headers = all("tr.table-group-header").map(&:text)
    # 2101-* codes are not in COURSE_GROUP_LABELS -> raw-suffix labels, alphabetical,
    # then Ungrouped (gened_cp has no tag).
    assert_equal 3, headers.size
    assert_match(/\AC\b/, headers[0])
    assert_match(/\AELEC\b/, headers[1])
    assert_match(/\AUngrouped\b/, headers[2])
    assert_text "2110101" # intro_computing under C
  end

  test "admin adds a course with a group tag inline" do
    course = Course.create!(course_no: "2110888", revision_year_be: 2565, name: "Addable")
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    click_on "Add Course"

    within("turbo-frame#program_course_form") do
      select "2110888 — Addable (2565)", from: "Course"
      fill_in "Group Code", with: "2101-C"
      click_on "Add Course"
    end

    assert_text "Course was added to the program."
    assert_equal "2101-C",
                 ProgramCourse.find_by(program: programs(:cp_bachelor), course: course).course_group_code
  end

  test "admin edits a pairing's group tag inline" do
    pc = program_courses(:gened_cp)
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    find("a[href='#{edit_program_program_course_path(programs(:cp_bachelor), pc)}']").click

    within("turbo-frame#program_course_form") do
      fill_in "Group Code", with: "2101-GENED"
      click_on "Save"
    end

    assert_text "Course group was updated."
    assert_equal "2101-GENED", pc.reload.course_group_code
  end

  test "admin removes a link without deleting the course" do
    pc = program_courses(:senior_cp)
    course_id = pc.course_id
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))

    accept_confirm do
      find("a[href='#{program_program_course_path(programs(:cp_bachelor), pc)}']").click
    end

    assert_text "Course was removed from the program."
    assert_nil ProgramCourse.find_by(id: pc.id)
    assert Course.exists?(course_id), "course itself must survive"
  end

  test "viewer sees the curriculum but no management controls" do
    sign_in users(:viewer)
    visit program_path(programs(:cp_bachelor))

    assert_text "Curriculum"
    assert_no_text "Add Course"
    assert_no_selector "a[href='#{edit_program_program_course_path(programs(:cp_bachelor), program_courses(:intro_cp))}']"
  end
end
```

- [ ] **Step 9: Add the course-form regression test.** Append inside the class in `test/system/courses_test.rb` — its `setup` block already signs in as admin, and its other tests already use `click_on "Update Course"` (default `f.submit` text) and label-based `fill_in`, so this test matches the file's conventions ("Abbreviation" is the real label at `app/views/courses/_form.html.haml:49`):

```ruby
  test "editing a course linked to two programs keeps both links and their tags" do
    course = courses(:intro_computing) # linked to cp_bachelor with tag 2101-C
    ProgramCourse.create!(program: programs(:cp_master), course: course,
                          course_group_code: "2102-ELEC")

    visit edit_course_path(course)
    fill_in "Abbreviation", with: "INTRO2"
    click_on "Update Course"

    assert_text "Course was successfully updated"
    assert_equal 2, course.reload.programs.count
    tags = course.program_courses.order(:id).pluck(:course_group_code)
    assert_includes tags, "2101-C"
    assert_includes tags, "2102-ELEC"
  end
```

- [ ] **Step 10: Run the full suite**

Run: `cd /home/dae/cp-api && bin/rails test && bin/rails test:system`
Expected: `0 failures, 0 errors` in both. System tests use headless Firefox ESR — if Select2's dropdown intercepts the native `select`, interact via `find(".select2-selection").click` then `find(".select2-results__option", text: "...").click` instead (known Capybara/Select2 friction; fix the test, not the app).

- [ ] **Step 11: Commit**

```bash
cd /home/dae/cp-api && hg add test/models/program_course_test.rb test/services/chulabooster/program_course_sync_test.rb test/services/legacy_course_group_backfill_test.rb test/system/program_curriculum_test.rb && hg commit test/fixtures/program_courses.yml test/models/program_course_test.rb test/services/chulabooster/program_course_sync_test.rb test/services/legacy_course_group_backfill_test.rb test/system/program_curriculum_test.rb test/system/courses_test.rb -m "Test course-group display, sync, backfill, and the m2m form regression

The sync/backfill write paths encode non-obvious policy (fill-blank-only,
conflicts report-only, placeholder links untouched) that a refactor could
silently break, and the course-form fix reverses a silent data-loss bug —
both need regression coverage.

- Model: label lookup + group ordering
- Services: ProgramCourseSync + LegacyCourseGroupBackfill bucket behavior,
  dry-run purity
- System: curriculum grouping, inline add/edit/remove, viewer read-only,
  two-program course edit keeps both links"
```

(If fixtures for `program_groups.yml` were modified in Step 6's note, add that file to the commit too.)
