# CS Study Track + Dissolve 0999 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the M.Sc.-CS regular/special (ภาคนอกเวลาราชการ) track split as `students.study_track`, dissolve the fictitious program `0999`, and stop upserts from overwriting program assignments.

**Architecture:** One nullable string column on `students`, backfilled by a service (`StudyTrackBackfill`) that classifies from three evidence sources (dept label, CB fee/project codes, student-ID segment) with dry-run/COMMIT semantics; a one-off `DissolveProgram0999` service re-homes 0999's students onto the regular CS lineage and deletes the row; a small hook in `Importers::Base` lets `StudentImporter` protect `program_id` on upsert.

**Tech Stack:** Rails 8.1, MySQL, Minitest + fixtures, HAML, server-side DataTables, Chulabooster::Client/SnapshotClient.

**Spec:** `docs/superpowers/specs/2026-08-21-cs-study-track-design.md`

## Global Constraints

- Version control is **Mercurial**: commit per task with explicit file lists; commit messages lead with WHY; trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. No push.
- Revert anchor (already captured, do not re-create): hg `6c96e6acc686`; full dev-DB dump at `tmp/backup-20260822-pre-study-track/cp_api_development-pre-study-track.sql`.
- Data tasks are dry-run by default; writes only with `COMMIT=1`. Keep all dry-run CSVs for dae's review.
- `study_track` values: exactly `"regular"` / `"special"`; null = unknown/not applicable. No importer attribute for it, ever.
- Special-label string (verbatim, from `enrollment_method`): `โครงการภาคนอกเวลาราชการ`.
- Do not touch production. Dev DB only.

---

### Task 1: Migration + model

**Files:**
- Create: `db/migrate/XXXXXX_add_study_track_to_students.rb` (via generator)
- Modify: `app/models/student.rb`
- Test: `test/models/student_test.rb`

**Interfaces:**
- Produces: `students.study_track` column; `Student::STUDY_TRACKS`, `Student::STUDY_TRACK_ICONS`, `Student::STUDY_TRACK_LABELS` (all frozen); blank→nil normalization + inclusion validation.

- [ ] **Step 1: Failing tests** — append to `test/models/student_test.rb`:

```ruby
test "study_track accepts regular, special, and nil" do
  s = students(:somchai)
  %w[regular special].each do |t|
    s.study_track = t
    assert s.valid?, "expected #{t} to be valid: #{s.errors.full_messages}"
  end
  s.study_track = nil
  assert s.valid?
end

test "study_track rejects unknown values and normalizes blank to nil" do
  s = students(:somchai)
  s.study_track = "evening"
  assert_not s.valid?
  s.study_track = ""
  assert s.valid?
  assert_nil s.study_track
end
```

(Use whatever the first existing student fixture is actually named — check `test/fixtures/students.yml` and reuse the same fixture the file already references.)

- [ ] **Step 2: Run** `bin/rails test test/models/student_test.rb` — expect failures (unknown attribute `study_track`).

- [ ] **Step 3: Migration** — `bin/rails g migration AddStudyTrackToStudents study_track:string`, body:

```ruby
class AddStudyTrackToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :study_track, :string
  end
end
```

`bin/rails db:migrate`.

- [ ] **Step 4: Model** — in `app/models/student.rb`, next to the existing constants (lines 2–20):

```ruby
# M.Sc.-CS study track (ภาคปกติ vs ภาคนอกเวลาราชการ, the department's "CT"
# cohorts). Null = unknown or not applicable (bachelors, unclassified eras).
# Backfilled from registrar evidence — see
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md. Deliberately
# has no importer attribute, so file imports can never touch it.
STUDY_TRACKS = %w[regular special].freeze
STUDY_TRACK_ICONS = { "regular" => "light_mode", "special" => "dark_mode" }.freeze
STUDY_TRACK_LABELS = { "regular" => "Regular", "special" => "นอกเวลาราชการ" }.freeze
```

next to the existing validations:

```ruby
validates :study_track, inclusion: { in: STUDY_TRACKS }, allow_nil: true
```

and a normalizer (matches the form's blank option submitting `""`):

```ruby
before_validation { self.study_track = nil if study_track.blank? }
```

- [ ] **Step 5: Run** `bin/rails test test/models/student_test.rb` — expect PASS.

- [ ] **Step 6: Commit** `db/migrate/*add_study_track*`, `db/schema.rb`, `app/models/student.rb`, `test/models/student_test.rb`.

---

### Task 2: Importer guard (program_id fill-blank-only on upsert)

**Files:**
- Modify: `app/services/importers/base.rb` (~line 141), `app/services/importers/student_importer.rb`
- Test: `test/services/importers/student_importer_test.rb` (+ a small CSV fixture in `test/fixtures/files/` if none fits)

**Interfaces:**
- Produces: `Importers::Base#update_protected_fields(existing)` → array of attr symbols stripped from upsert updates (default `[]`).

- [ ] **Step 1: Failing test** — in `student_importer_test.rb`, using the existing `create_data_import` helper (switch `mode:` to `"upsert"`). Create a CSV fixture `test/fixtures/files/students_upsert_program.csv`:

```csv
student_id,first_name,last_name,first_name_th,last_name_th,admission_year_be,program_name
<EXISTING_SID>,Keep,Program,ชื่อ,สกุล,<YEAR>,วิทยาศาสตร์คอมพิวเตอร์
```

where `<EXISTING_SID>`/`<YEAR>` match a student fixture that HAS a program pointing at a non-CS program (so a successful resolve would *change* it). Tests:

```ruby
test "upsert does not overwrite an existing program assignment" do
  student = students(:somchai)  # fixture with program set
  original_program_id = student.program_id
  di = create_data_import("students_upsert_program.csv",
    column_mapping: { "student_id" => "A: student_id", "first_name" => "B: first_name",
                      "last_name" => "C: last_name", "first_name_th" => "D: first_name_th",
                      "last_name_th" => "E: last_name_th", "admission_year_be" => "F: admission_year_be",
                      "program_name" => "G: program_name" })
  di.update!(mode: "upsert")
  Importers::StudentImporter.new(di).call
  assert_equal original_program_id, student.reload.program_id
end

test "upsert fills a blank program assignment" do
  student = students(:somchai)
  student.update_columns(program_id: nil)
  di = ... same ...
  Importers::StudentImporter.new(di).call
  assert_not_nil student.reload.program_id
end
```

(Adapt fixture names/CSV to what `test/fixtures/students.yml` actually contains; the CSV's student_id must equal the fixture's. If resolving "วิทยาศาสตร์คอมพิวเตอร์" needs program fixtures, reuse existing `programs.yml` entries.)

- [ ] **Step 2: Run** — first test FAILS (program gets overwritten today), second may already pass.

- [ ] **Step 3: Implement** — `base.rb` line ~141:

```ruby
existing.assign_attributes(attrs.except(*unique_key_fields, *update_protected_fields(existing)))
```

and among Base's private/protected helpers:

```ruby
# Attributes a subclass refuses to overwrite on an existing record in
# upsert mode (returned per-record). Default: none.
def update_protected_fields(_existing)
  []
end
```

`student_importer.rb` (private):

```ruby
# Program assignment is authoritative once set — same policy as the CB
# student sync. A re-imported file may fill a blank program but never
# change it; without this, name-based resolution re-picks a revision on
# every upsert, and an unresolvable value would even null the assignment
# (transform_attributes sets attrs[:program_id] = program&.id).
def update_protected_fields(existing)
  existing.program_id.present? ? [ :program_id ] : []
end
```

Also extend the `program_name` attribute's `help:` text with: `"On upsert, existing students keep their current program — file values only fill blanks."`

- [ ] **Step 4: Run** `bin/rails test test/services/importers/student_importer_test.rb` — PASS.

- [ ] **Step 5: Commit** the three code files + fixture CSV.

---

### Task 3: `StudyTrackBackfill` service + rake task

**Files:**
- Create: `app/services/study_track_backfill.rb`, `lib/tasks/students.rake`
- Test: `test/services/study_track_backfill_test.rb`

**Interfaces:**
- Consumes: `Student::STUDY_TRACKS` (Task 1).
- Produces: `StudyTrackBackfill.new(cb_rows:, commit:, out_dir:, io:)#run`; pure `#decide(student, cb_row)` → `Decision(track, evidence, review_reason)`; rake `students:backfill_study_track`.

- [ ] **Step 1: Failing tests** — `test/services/study_track_backfill_test.rb`, driving `#decide` with fixture-built students (no CB network):

```ruby
require "test_helper"

class StudyTrackBackfillTest < ActiveSupport::TestCase
  LABEL = StudyTrackBackfill::SPECIAL_LABEL

  def backfill = StudyTrackBackfill.new(cb_rows: {}, commit: false)

  def cs_student(year:, sid: nil, label: nil)
    prog = programs(<a CS-group program fixture>)
    Student.new(student_id: sid || "#{(year - 2500)}70000021", admission_year_be: year,
                program: prog, enrollment_method: label,
                first_name: "a", last_name: "b", first_name_th: "ก", last_name_th: "ข")
  end

  test "label marks special in any group" do
    d = backfill.decide(cs_student(year: 2545, label: LABEL), nil)
    assert_equal "special", d.track
  end

  test "cb project 212 with special fee is special (2533-2553)" do
    d = backfill.decide(cs_student(year: 2545), { "project" => "212", "fee_type" => "07" })
    assert_equal "special", d.track
  end

  test "cb project 201 with regular fee is regular (2533-2553)" do
    d = backfill.decide(cs_student(year: 2545), { "project" => "201", "fee_type" => "01" })
    assert_equal "regular", d.track
  end

  test "label vs classifier conflict goes to review" do
    d = backfill.decide(cs_student(year: 2545, label: LABEL), { "project" => "201", "fee_type" => "01" })
    assert_nil d.track
    assert d.review_reason.present?
  end

  test "segment 71 is special, 70 regular (2554-2560)" do
    assert_equal "special", backfill.decide(cs_student(year: 2556, sid: "5671000021"), nil).track
    assert_equal "regular", backfill.decide(cs_student(year: 2556, sid: "5670000021"), nil).track
  end

  test "pre-2533 CS is regular; 2561+ CS is nil; non-CS unlabeled is nil" do
    assert_equal "regular", backfill.decide(cs_student(year: 2530), nil).track
    assert_nil backfill.decide(cs_student(year: 2563, sid: "6372000021"), nil).track
  end

  test "CS 2533-2553 with no CB row goes to review" do
    d = backfill.decide(cs_student(year: 2545), nil)
    assert_nil d.track
    assert_match(/not in CB/, d.review_reason)
  end
end
```

- [ ] **Step 2: Run** — FAIL (class missing).

- [ ] **Step 3: Implement** `app/services/study_track_backfill.rb`:

```ruby
require "csv"

# Backfills students.study_track ("regular"/"special") for the M.Sc.-CS
# track split (ภาคนอกเวลาราชการ, the department's CT cohorts) from three
# independent evidence sources; dry-run unless commit. Never overwrites an
# already-set value. Rules and their validation:
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md.
class StudyTrackBackfill
  SPECIAL_LABEL = "โครงการภาคนอกเวลาราชการ"
  SPECIAL_FEES = %w[4 04 07].freeze
  REGULAR_FEES = %w[1 01].freeze
  CB_RULE_YEARS = (2533..2553)      # fee/project partition is exact here
  SEGMENT_RULE_YEARS = (2554..2560) # fees blur; ID digits 3-4 still split

  Decision = Struct.new(:track, :evidence, :review_reason)

  def initialize(cb_rows:, commit: false, out_dir: Rails.root.join("tmp", "study_track_backfill"), io: $stdout)
    @cb_rows, @commit, @out_dir, @io = cb_rows, commit, Pathname(out_dir), io
  end

  def run
    FileUtils.mkdir_p(@out_dir)
    assigned = Hash.new(0)
    assignments = []
    reviews = []

    Student.includes(program: :program_group).order(:admission_year_be, :student_id).find_each do |student|
      decision = decide(student, @cb_rows[student.student_id])
      if student.study_track.present?
        if decision.track && decision.track != student.study_track
          reviews << [student, decision, "already #{student.study_track}, evidence now says #{decision.track}"]
        end
        next
      end
      if decision.review_reason
        reviews << [student, decision, decision.review_reason]
      elsif decision.track
        assignments << [student, decision]
        assigned[[group_code(student), decision.track]] += 1
        student.update!(study_track: decision.track) if @commit
      end
    end

    write_csv("assignments.csv", %w[student_id name group year track evidence],
              assignments.map { |s, d| [s.student_id, s.display_name, group_code(s), s.admission_year_be, d.track, d.evidence] })
    write_csv("review.csv", %w[student_id name group year enrollment_method reason],
              reviews.map { |s, d, r| [s.student_id, s.display_name, group_code(s), s.admission_year_be, s.enrollment_method, r] })

    @io.puts "#{@commit ? 'COMMITTED' : 'DRY-RUN'}: #{assignments.size} assignments, #{reviews.size} review rows -> #{@out_dir}"
    assigned.sort.each { |(g, t), n| @io.puts "  #{g} #{t}: #{n}" }
    { assignments: assignments.size, reviews: reviews.size }
  end

  # Pure classification; returns Decision. Order (spec): label -> CB
  # fee/project (CS 2533-2553) -> ID segment (CS 2554-2560) -> regular for
  # CS <= 2532 -> nil. Label-vs-classifier disagreement is a tripwire.
  def decide(student, cb)
    labeled = student.enrollment_method.to_s.strip == SPECIAL_LABEL
    cs = group_code(student) == "CS"
    year = student.admission_year_be

    classifier, evidence, why_unclassified =
      if cs && CB_RULE_YEARS.cover?(year)
        track = cb_classify(cb)
        [track, ("cb:project=#{cb&.dig('project')},fee=#{cb&.dig('fee_type')}" if track),
         (cb.nil? ? "CS #{year}: not in CB export" : "CS #{year}: unrecognized CB combo project=#{cb['project']} fee=#{cb['fee_type']}")]
      elsif cs && SEGMENT_RULE_YEARS.cover?(year)
        track = segment_classify(student.student_id)
        [track, ("segment:#{student.student_id[2, 2]}" if track), "CS #{year}: unrecognized ID segment #{student.student_id[2, 2]}"]
      else
        [nil, nil, nil]
      end

    if labeled && classifier == "regular"
      Decision.new(nil, nil, "label says special but classifier says regular (#{evidence})")
    elsif labeled
      Decision.new("special", "label:enrollment_method")
    elsif classifier
      Decision.new(classifier, evidence)
    elsif cs && year <= 2532
      Decision.new("regular", "pre-special-era")
    elsif why_unclassified
      Decision.new(nil, nil, why_unclassified)
    else
      Decision.new(nil, nil, nil) # out of scope: no assignment, no review noise
    end
  end

  private

  def group_code(student) = student.program&.program_group&.code

  def cb_classify(cb)
    return nil unless cb
    project, fee = cb["project"].to_s, cb["fee_type"].to_s
    return "special" if project == "212" && SPECIAL_FEES.include?(fee)
    return "regular" if project == "201" && REGULAR_FEES.include?(fee)
    nil
  end

  def segment_classify(sid)
    return nil unless sid.to_s.length == 10
    { "71" => "special", "70" => "regular" }[sid[2, 2]]
  end

  def write_csv(name, headers, rows)
    CSV.open(@out_dir.join(name), "w") do |csv|
      csv << headers
      rows.each { |r| csv << r }
    end
  end
end
```

`lib/tasks/students.rake`:

```ruby
namespace :students do
  desc "Backfill students.study_track from enrollment label + CB evidence. " \
       "Dry-run by default; COMMIT=1 to write, SNAPSHOT_DIR= to read a CB snapshot instead of live."
  task backfill_study_track: :environment do
    client = ENV["SNAPSHOT_DIR"].present? ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    cb_rows = {}
    client.each_row("students") { |r| cb_rows[r["student_id"].to_s] = r }
    puts "CB students loaded: #{cb_rows.size}"
    StudyTrackBackfill.new(cb_rows: cb_rows, commit: ENV["COMMIT"] == "1").run
  end
end
```

- [ ] **Step 4: Run** the test file — PASS.
- [ ] **Step 5: Commit** the three new files.

---

### Task 4: `DissolveProgram0999` service + rake task + seeds

**Files:**
- Create: `app/services/dissolve_program_0999.rb`, `lib/tasks/programs.rake` (or extend if exists)
- Modify: `db/seeds/programs.rb` (remove 0999 entry, leave tombstone comment)
- Test: `test/services/dissolve_program_0999_test.rb`

**Interfaces:**
- Produces: `DissolveProgram0999.new(commit:, io:)#run`; rake `programs:dissolve_0999`.

- [ ] **Step 1: Failing test** (use/create program fixtures: a CS group with `0038`/2538 and `0999`/2540, one student on 0999 with `admission_year_be: 2545`):

```ruby
require "test_helper"

class DissolveProgram0999Test < ActiveSupport::TestCase
  test "dry-run reports moves but changes nothing" do
    <student fixture on 0999>
    DissolveProgram0999.new(commit: false, io: StringIO.new).run
    assert Program.exists?(program_code: "0999")
  end

  test "commit moves students to latest regular revision <= admission year and deletes 0999" do
    student = <student fixture on 0999, year 2545>
    DissolveProgram0999.new(commit: true, io: StringIO.new).run
    assert_equal "0038", student.reload.program.program_code
    assert_not Program.exists?(program_code: "0999")
  end
end
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** `app/services/dissolve_program_0999.rb`:

```ruby
# One-off: dissolves the synthetic program row "0999" (see
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md — the real
# B.E. 2540 registration is the special program, now recorded per-student
# in students.study_track, not a curriculum revision). Students move to
# the latest remaining CS revision started on or before their admission
# year; the row is then destroyed (program_courses cascade).
class DissolveProgram0999
  def initialize(commit: false, io: $stdout)
    @commit, @io = commit, io
  end

  def run
    program = Program.find_by(program_code: "0999")
    return @io.puts("0999 not found — already dissolved.") unless program

    replacements = program.program_group.programs.where.not(id: program.id)
    moves = program.students.order(:admission_year_be, :student_id).map do |s|
      target = replacements.where(year_started_be: ..s.admission_year_be).order(year_started_be: :desc).first
      raise "no replacement revision for #{s.student_id} (#{s.admission_year_be})" unless target
      [s, target]
    end

    moves.group_by { |s, t| [s.admission_year_be, t.program_code] }.sort.each do |(year, code), pairs|
      @io.puts "  #{year} -> #{code}: #{pairs.size}"
    end
    @io.puts "program_courses rows on 0999 (will cascade): #{program.program_courses.count}"

    if @commit
      Program.transaction do
        moves.each { |s, target| s.update!(program: target) }
        raise "students still attached" unless program.students.reload.count.zero?
        program.destroy!
      end
      @io.puts "COMMITTED: #{moves.size} students moved, 0999 destroyed."
    else
      @io.puts "DRY-RUN: would move #{moves.size} students, then destroy 0999."
    end
  end
end
```

`lib/tasks/programs.rake` — add task with the same desc style (`COMMIT=1` contract) calling the service.

- [ ] **Step 4: Seeds** — delete the `0999` line from `db/seeds/programs.rb`, in its place:

```ruby
# NOTE: deliberately NO row for the B.E. 2540 M.Sc.-CS registration
# (CB program 175211001997, major_code 21100). That is the special
# program (ภาคนอกเวลาราชการ — the department's "CT" cohorts, intakes
# 2533-2560), recorded per-student in students.study_track; it is not a
# curriculum revision of the regular CS lineage. A synthetic stand-in
# code "0999" was dissolved on 2026-08-22 — do not re-add. See
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md.
```

- [ ] **Step 5: Run** tests — PASS. **Step 6: Commit** all four files.

---

### Task 5: UI (badges, show page, index column + filter, form)

**Files:**
- Modify: `app/assets/stylesheets/application.scss` (badge block ~line 197), `app/views/students/show.html.haml` (after the Program row, ~line 30), `app/views/students/index.html.haml` (filters + `<th>`), `app/views/students/_form.html.haml` (after program select ~line 60), `app/controllers/students_controller.rb` (COLUMNS_MAP, datatable data row, filtered_students, permit)

**Interfaces:**
- Consumes: `Student::STUDY_TRACK_LABELS`, `STUDY_TRACK_ICONS` (Task 1).

- [ ] **Step 1: SCSS** — next to the existing frosted badge classes:

```scss
// Study track (M.Sc. programs): regular vs นอกเวลาราชการ (special/evening program)
.badge-track-regular { background-color: rgba($secondary, 0.2); color: tint-color($secondary, 30%); border: 1px solid rgba($secondary, 0.4); }
.badge-track-special { background-color: rgba($warning, 0.15);  color: $warning;   border: 1px solid rgba($warning, 0.35); }
```

(Match the exact property style of neighbors; if `tint-color` isn't already used in the file, use the plain `$secondary` form the neighbors use.) Run `bin/rails dartsass:build`.

- [ ] **Step 2: Show page** — after the Program `%dd` block:

```haml
- if @student.study_track.present?
  %dt.col-sm-3 Study Track
  %dd.col-sm-9
    %span.badge{class: "badge-track-#{@student.study_track}"}= Student::STUDY_TRACK_LABELS[@student.study_track]
```

- [ ] **Step 3: Index** — new column between Status and Actions (`%th Study Track` before `%th Actions`); new filter select in the filter row:

```haml
.d-flex.align-items-center.gap-2{style: "min-width: 160px"}
  %span.form-label.mb-0.small.text-muted Track
  = select_tag "filter-track", options_for_select([["All", ""]] + Student::STUDY_TRACKS.map { |t| [Student::STUDY_TRACK_LABELS[t], t] }), data: { controller: "select2", datatable_target: "filter", action: "change->datatable#filter", datatable_column_index: "6" }
```

- [ ] **Step 4: Controller** — `COLUMNS_MAP`: add `6 => "students.study_track"` (Actions stays unmapped). In `datatable`'s row array, insert before the actions cell:

```ruby
(student.study_track ? "<span class=\"badge badge-track-#{student.study_track}\">#{ERB::Util.html_escape(Student::STUDY_TRACK_LABELS[student.study_track])}</span>" : "").to_s,
```

In `filtered_students`, add:

```ruby
col_search_track = params.dig(:columns, "6", :search, :value).to_s.strip
base = base.where("students.study_track" => col_search_track) if col_search_track.present?
```

In `student_params` permit list: add `:study_track`.

- [ ] **Step 5: Form** — after the program select:

```haml
.col-md-6
  .mb-3
    = f.label :study_track, "Study Track", class: "form-label"
    = f.select :study_track, options_for_select(Student::STUDY_TRACKS.map { |t| [Student::STUDY_TRACK_LABELS[t], t, { data: { icon: Student::STUDY_TRACK_ICONS[t] } }] }, student.study_track), { include_blank: "— Unknown —" }, class: "form-select", data: { controller: "select2" }
```

(Match the wrapper divs of the neighboring fields exactly.)

- [ ] **Step 6:** Check `docs/backlog.md` triggered items (entity show page changed) — apply or consciously skip, note which in the commit message.

- [ ] **Step 7:** Boot check: `bin/rails runner "puts 1"` + run the full model/controller test suites touched: `bin/rails test test/models/student_test.rb test/controllers/students_controller_test.rb` (if the controller test exists). Manual smoke happens post-backfill in Task 7. **Commit** all files.

---

### Task 6: Documentation

**Files:**
- Modify: `docs/chulabooster-program-crosswalk.md`, `CLAUDE.md`

- [ ] **Step 1: Crosswalk doc** — add a dated section: CB `175211001997` = the special program's registration (major 21100, blank name, rev 1997); no local Program row (synthetic `0999` dissolved 2026-08-22); track recorded in `students.study_track`; the classifier (label / fee+project 2533–2553 / segment 2554–2560) with the validation numbers (717/719 label agreement, 675/684 book agreement); open questions: SE/CM twin semantics, CS segment-72 (2562+).

- [ ] **Step 2: CLAUDE.md** — one bullet under Data Model Conventions:

```markdown
- **`students.study_track`** (`regular`/`special`, null = unknown): the M.Sc.-CS
  ภาคนอกเวลาราชการ track split (dept "CT" cohorts, intakes 2533–2560). Backfilled from
  registrar evidence (`students:backfill_study_track`, dry-run/`COMMIT=1`); deliberately
  has NO importer attribute. The synthetic program `0999` was dissolved into the regular
  CS lineage (`programs:dissolve_0999`) — do not re-add; the real B.E. 2540 registration
  is CB `175211001997` (the special program). Importer upserts never overwrite an
  existing `program_id` (fill-blank-only). Spec: `docs/superpowers/specs/2026-08-21-cs-study-track-design.md`.
```

- [ ] **Step 3: Commit** both files.

---

### Task 7: Execute data tasks on dev + verify

- [ ] **Step 1:** Confirm backup exists: `tmp/backup-20260822-pre-study-track/cp_api_development-pre-study-track.sql` (already taken; abort if missing).
- [ ] **Step 2:** `bin/rails students:backfill_study_track` (dry-run, live CB). Inspect summary + `tmp/study_track_backfill/*.csv`. Sanity: ~700 CS assignments (both tracks) + SE/CM label specials; review.csv small (dozens, mostly 2539-era oddities/notinCB).
- [ ] **Step 3:** `COMMIT=1 bin/rails students:backfill_study_track`. Re-run dry-run → should report ~0 new assignments (idempotent).
- [ ] **Step 4:** `bin/rails programs:dissolve_0999` (dry-run) — expect 730 moves, all to 0038, years 2540–2556. Then `COMMIT=1 bin/rails programs:dissolve_0999`.
- [ ] **Step 5:** Verify in `bin/rails runner`: `Program.find_by(program_code: "0999")` nil; 0038 student count grew by 730; `Student.group(:study_track).count`; CS special ≈ 690–720.
- [ ] **Step 6:** Full unit suite: `bin/rails test`. Fix regressions if any.
- [ ] **Step 7:** Copy the dry-run CSVs somewhere stable for dae's review (they already live in `tmp/study_track_backfill/`; keep, don't commit).
- [ ] **Step 8:** No commit (data-only step) unless fixes were needed.

---

## Self-review checklist (run after writing, before executing)

- Spec coverage: migration/model ✓ (T1), backfill rules ✓ (T3), dissolution + seeds ✓ (T4), importer guard ✓ (T2), UI ✓ (T5), docs ✓ (T6), rollout dev half ✓ (T7; production deliberately deferred to dae).
- Types: `decide` returns `Decision(track, evidence, review_reason)` everywhere; `update_protected_fields` symbol array in both files.
- Out of scope (per spec): book add-missing, SE/CM twins, segment-72, CT notation, exporter column (consciously omitted — export mirrors the table minus the new column for now; note for dae).
