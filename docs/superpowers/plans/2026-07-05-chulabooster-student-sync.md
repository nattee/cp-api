# ChulaBooster Student Sync — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `chulabooster:sync_students` — the first CB→local write path: create local `Student` records for the 1,441 CB-only students (dry-run by default, `COMMIT=1` to write) plus two report-only discrepancy checks on existing students.

**Architecture:** Three small service units under `app/services/chulabooster/` (`StatusCodes` code-family table, `ProgramResolver` for the two-layer program resolution, `StudentSync` orchestrating both passes and writing report CSVs), a rake task, a seeds change populating `Program.alternative_program_code`, one migration (`students.cb_status_code`), and a static admin pointer page. Acceptance is empirical: the dry-run against the existing snapshot must reproduce the numbers simulated during design.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, MySQL 8. VCS is **Mercurial (hg)** — not git.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-05-chulabooster-student-sync-design.md`. Evidence & policy: `docs/chulabooster-program-crosswalk.md`, `docs/chulabooster-student-status-crosswalk.md`. Do not contradict the policy sections.
- **Never modify existing student records**, with ONE exception: `cb_status_code` (a new, mirror-only column) may be refreshed on matched students, and only when `commit: true`, via `update_column` (no validations/callbacks/updated_at).
- **Dry-run is the default.** No DB write of any kind unless `COMMIT=1`. A dry-run must leave every table's row count unchanged.
- **Every guess writes a `remark` flag** (heuristic group, 7-digit default, year-fallback, twin default). Discrepancies are **reported to CSV, never auto-corrected**.
- **hg, not git**: commit per task with **explicit file paths** (repo carries unrelated dirty files — NEVER commit `config/credentials.yml.enc`, `CLIENT_GUIDE.md`, `access-natte.txt`). Messages lead with WHY (first paragraph = motivation), end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **Testing convention (overrides TDD default):** per CLAUDE.md, test files are written *after* the feature, following a discussion with the user. Tasks verify via `ruby -c`, `bin/rails runner` probes, and the Task 8 acceptance run. The final task STOPS to ask the user about tests — do not write test files in Tasks 1–9.
- **Acceptance numbers (dry-run vs snapshot `tmp/chulabooster_snapshot/full-2026-07-03`):** cb_only=1441; unresolved=9 (all `major_code=21103`); creatable+errors=1432 (≥1 error: one student has a blank lastname); heuristic-flagged=506; twin-flagged=328; matched=7135; program_discrepancies=2 (student_ids 3971081121, 3971235521); stale_active=765.
- If that snapshot dir is missing, regenerate: `bin/rails chulabooster:snapshot` (~40 min) — do NOT hit CB live for iterative testing.

---

### Task 1: Commit the pending prerequisite work

The snapshot tool and crosswalk docs are prerequisites of this feature but are still uncommitted. Land them first so every later task builds on committed state.

**Files (commit only — no edits):**
- `app/services/chulabooster/snapshotter.rb`, `app/services/chulabooster/snapshot_client.rb` (untracked → add)
- `docs/chulabooster-program-crosswalk.md`, `docs/chulabooster-student-status-crosswalk.md`, `docs/superpowers/specs/2026-07-05-chulabooster-student-sync-design.md` (untracked → add)
- `lib/tasks/chulabooster.rake`, `CLAUDE.md` (modified)

- [ ] **Step 1: Verify the working state** — Run: `hg status`. Expected: the files above as `M`/`?`, plus unrelated `M config/credentials.yml.enc`, `? CLIENT_GUIDE.md`, `? access-natte.txt`, `? docs/superpowers/plans/*.md` (leave all four alone; plans/specs of the *rename* project may also appear — leave them).

- [ ] **Step 2: Add and commit with explicit files**

```bash
cd /home/dae/cp-api
hg add app/services/chulabooster/snapshotter.rb app/services/chulabooster/snapshot_client.rb \
  docs/chulabooster-program-crosswalk.md docs/chulabooster-student-status-crosswalk.md \
  docs/superpowers/specs/2026-07-05-chulabooster-student-sync-design.md
hg commit app/services/chulabooster/snapshotter.rb app/services/chulabooster/snapshot_client.rb \
  docs/chulabooster-program-crosswalk.md docs/chulabooster-student-status-crosswalk.md \
  docs/superpowers/specs/2026-07-05-chulabooster-student-sync-design.md \
  lib/tasks/chulabooster.rake CLAUDE.md \
  -m "Cache ChulaBooster pulls and record the crosswalk facts the sync must obey

Re-running analysis against ChulaBooster meant re-pulling ~50k rows (tens of
minutes) every time, and the hard-won facts about CB's program/status
encodings lived only in chat logs and hg-ignored tmp/ files. This lands a
snapshot cache (JSONL dump + drop-in read-back client) so reconciliation and
analysis run offline, plus the two crosswalk documents that Phase 2a's
student sync is designed against, and the sync's approved design spec.

- chulabooster:snapshot rake task + Snapshotter/SnapshotClient
- SNAPSHOT_DIR= support on chulabooster:reconcile
- docs: program crosswalk (incl. CM/CD student_id heuristic + review findings),
  student status crosswalk (CB more authoritative than stale local 'active'),
  student-sync design spec
- CLAUDE.md: ChulaBooster Integration section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Verify** — Run: `hg status`. Expected: only `M config/credentials.yml.enc` + the unrelated untracked files remain.

---

### Task 2: Populate `Program.alternative_program_code` via seeds

**Files:**
- Modify: `db/seeds/programs.rb`

**Interfaces:**
- Produces: every non-OTHER `Program` row has `alternative_program_code` set to its CB major_code (`"21100"` CP/CM/CD, `"21101"` CS, `"21102"` SE, `"21104"` CEDT). `ProgramResolver` (Task 5) does NOT query this column (it groups via `program_group.code`), but populating it makes the crosswalk queryable and satisfies the spec's prerequisite.

- [ ] **Step 1: Add the mapping constant and one line in the seed loop.** In `db/seeds/programs.rb`, directly above the `programs.each do |group_code, revisions|` loop (line ~85), insert:

```ruby
# ChulaBooster major_code per program group (see docs/chulabooster-program-crosswalk.md).
# CP/CM/CD share 21100 — CB's major_code does not distinguish degree level.
CB_MAJOR_CODES = {
  "CP" => "21100", "CM" => "21100", "CD" => "21100",
  "CS" => "21101", "SE" => "21102", "CEDT" => "21104",
  "OTHER" => nil
}.freeze
```

and inside the loop body, next to `attrs[:program_group] = group`:

```ruby
    attrs[:alternative_program_code] = CB_MAJOR_CODES[group_code]
```

- [ ] **Step 2: Re-seed just this file** — Run: `bin/rails runner "load Rails.root.join('db/seeds/programs.rb')"` . Expected: exits cleanly.

- [ ] **Step 3: Verify** — Run:
```bash
bin/rails runner 'puts Program.joins(:program_group).where.not(program_groups: { code: "OTHER" }).group(:alternative_program_code).count.inspect'
```
Expected: `{"21100" => 28, "21101" => 6, "21102" => 10, "21104" => 1}` (45 total: CP 8 + CM 8 + CD 12 = 28, CS 6, SE 10, CEDT 1). *(Plan originally said 30/9 — a counting error, corrected during execution; verified against the actual group counts.)* Also `bin/rails runner 'puts Program.find_by(program_code: "0000").alternative_program_code.inspect'` → `nil`.

- [ ] **Step 4: Commit**
```bash
hg commit db/seeds/programs.rb -m "Record each program's ChulaBooster major_code so the crosswalk is queryable

The CB student sync resolves students by CB major_code, but the mapping to
our program groups lived only in a doc. Seed it into
Program.alternative_program_code (the field reserved for exactly this),
noting that CP/CM/CD share 21100 by CB's design.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Migration — `students.cb_status_code`

**Files:**
- Create: `db/migrate/<timestamp>_add_cb_status_code_to_students.rb` (via generator)
- Modify (auto): `db/schema.rb`

**Interfaces:**
- Produces: nullable string column `students.cb_status_code` (CB's raw status code, e.g. `"13"` — finer resolution than the 5-value `status` enum).

- [ ] **Step 1: Generate** — Run: `bin/rails g migration AddCbStatusCodeToStudents cb_status_code:string`
- [ ] **Step 2: Confirm the generated body is exactly** (edit if the generator added anything else):
```ruby
class AddCbStatusCodeToStudents < ActiveRecord::Migration[8.1]
  def change
    add_column :students, :cb_status_code, :string
  end
end
```
- [ ] **Step 3: Migrate** — Run: `bin/rails db:migrate && bin/rails db:test:prepare`. Expected: clean; `db/schema.rb` gains the column.
- [ ] **Step 4: Verify** — Run: `bin/rails runner 'puts Student.column_names.include?("cb_status_code")'` → `true`.
- [ ] **Step 5: Commit**
```bash
hg commit db/migrate/*_add_cb_status_code_to_students.rb db/schema.rb \
  -m "Keep ChulaBooster's raw status code alongside our coarser status enum

CB's student_status carries finer resolution than our 5-value status field
(e.g. distinct graduation/retirement codes). Collapsing it on import would
discard information we cannot recover; a mirror column preserves it.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `Chulabooster::StatusCodes`

**Files:**
- Create: `app/services/chulabooster/status_codes.rb`

**Interfaces:**
- Produces: `Chulabooster::StatusCodes.to_local(code) → "active" | "graduated" | "retired" | nil` (nil = unknown code). Used by Task 6.

- [ ] **Step 1: Write the module** (complete file):

```ruby
module Chulabooster
  # Crosswalk from CB's raw student_status codes to our Student::STATUSES values.
  # Empirically derived and validated (~99% against locally-confirmed graduated/
  # retired students) — see docs/chulabooster-student-status-crosswalk.md.
  # CB has never documented these codes; unknown codes map to nil so callers
  # can fall back to "unknown" and report, never crash.
  module StatusCodes
    ACTIVE    = %w[00 01 05].freeze
    GRADUATED = %w[11 12 13].freeze
    RETIRED   = %w[21 23 24 25 27 28 30 31 32 33 35 36 37 39].freeze

    def self.to_local(code)
      c = code.to_s.strip
      return "active"    if ACTIVE.include?(c)
      return "graduated" if GRADUATED.include?(c)
      return "retired"   if RETIRED.include?(c)
      nil
    end
  end
end
```

- [ ] **Step 2: Verify** — Run:
```bash
ruby -c app/services/chulabooster/status_codes.rb
bin/rails runner 'puts [Chulabooster::StatusCodes.to_local("13"), Chulabooster::StatusCodes.to_local("00"), Chulabooster::StatusCodes.to_local("31"), Chulabooster::StatusCodes.to_local("99").inspect].join(" | ")'
```
Expected: `Syntax OK` then `graduated | active | retired | nil`.

- [ ] **Step 3: Commit**
```bash
hg commit app/services/chulabooster/status_codes.rb \
  -m "Codify the empirically-derived CB status-code families

The CB student sync needs to derive our status enum from CB's undocumented
numeric codes; the validated family table lived only in a doc. Unknown codes
return nil so callers report rather than crash.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `Chulabooster::ProgramResolver`

**Files:**
- Create: `app/services/chulabooster/program_resolver.rb`

**Interfaces:**
- Consumes: local `Program`/`ProgramGroup`/`Student` tables (loaded once in the constructor).
- Produces: `Chulabooster::ProgramResolver#resolve(major_code:, student_id:, admission_year_be:) → Result` where `Result` is a Struct with members `program` (Program or nil), `group` (String or nil), `flags` (Array of human-readable assumption strings), `failure` (String or nil), `heuristic` (bool — the 21100 student_id heuristic was used), `twin_tie` (bool — a twin-pair default was applied). `failure` non-nil ⇒ unresolvable. Used by Task 6.

- [ ] **Step 1: Write the class** (complete file):

```ruby
module Chulabooster
  # Resolves a CB student row to a local Program, per the two-layer algorithm in
  # docs/chulabooster-program-crosswalk.md (§4, §6): major_code → program_group
  # (with the student_id-segment heuristic + year-existence fallback for the
  # shared 21100), then admission-year window → revision (majority-enrollment
  # default on twin ties). Loads all programs + enrollment counts once — build
  # one instance per sync run.
  class ProgramResolver
    MAJOR_TO_GROUP = { "21101" => "CS", "21102" => "SE", "21104" => "CEDT" }.freeze
    CM_SEGMENTS = %w[70 72].freeze
    CD_SEGMENTS = %w[71 73].freeze
    # Year-existence fallback order: a graduate-range segment falls back to the
    # OTHER graduate group before bachelor (validated: the two pre-1998 seg-71
    # students are confirmed CM, not CP). See crosswalk doc §4.
    FALLBACK_ORDER = { "CD" => %w[CM CP], "CM" => %w[CD CP], "CP" => %w[CM CD] }.freeze

    Result = Struct.new(:program, :group, :flags, :failure, :heuristic, :twin_tie, keyword_init: true)

    def initialize
      @programs_by_group = Hash.new { |h, k| h[k] = [] }
      Program.includes(:program_group).where.not(program_groups: { code: "OTHER" }).each do |p|
        @programs_by_group[p.program_group.code] << [p.year_started_be, p]
      end
      @programs_by_group.each_value { |v| v.sort_by!(&:first) }
      @enrollment = Student.group(:program_id).count
    end

    def resolve(major_code:, student_id:, admission_year_be:)
      flags = []
      heuristic = false
      mc = major_code.to_s

      group = MAJOR_TO_GROUP[mc]
      if group.nil?
        return Result.new(failure: "unmapped major_code #{mc.inspect}", flags: flags) unless mc == "21100"
        heuristic = true
        group = group_from_student_id(student_id.to_s, flags)
        # Year-existence fallback (validated 146/146 on segment 71): if the guessed
        # group has no program old enough, the guess is impossible — try the others.
        if candidates(group, admission_year_be).empty?
          alt = FALLBACK_ORDER.fetch(group).find { |g| candidates(g, admission_year_be).any? }
          if alt
            flags << "no #{group} program existed by #{admission_year_be}; reassigned to #{alt}"
            group = alt
          end
        end
      end

      cands = candidates(group, admission_year_be)
      if cands.empty?
        return Result.new(group: group, flags: flags, heuristic: heuristic,
                          failure: "no #{group} program with year_started_be <= #{admission_year_be}")
      end

      best_year = cands.map(&:first).max
      twins = cands.select { |(y, _)| y == best_year }.map(&:last)
      program, twin_tie = pick_twin(twins, flags)
      Result.new(program: program, group: group, flags: flags, heuristic: heuristic, twin_tie: twin_tie)
    end

    private

    def candidates(group, admission_year_be)
      @programs_by_group[group].select { |(y, _)| y <= admission_year_be }
    end

    # 10-digit IDs carry a degree-level code at positions 2-3 (validated 99.97%);
    # 7-digit legacy IDs have no such segment — all 442 known ones are CP.
    def group_from_student_id(sid, flags)
      if sid.length == 10
        seg = sid[2, 2]
        group = if CM_SEGMENTS.include?(seg) then "CM"
                elsif CD_SEGMENTS.include?(seg) then "CD"
                else "CP"
                end
        flags << "program group #{group} inferred from student_id pattern " \
                 "(major_code 21100 is shared by CP/CM/CD) — verify"
        group
      else
        flags << "program group CP assumed (legacy #{sid.length}-digit student_id, " \
                 "major_code 21100; all known legacy-ID students are CP) — verify"
        "CP"
      end
    end

    # Twin ties: assign to the twin with the most current local students
    # (maximum-likelihood; see crosswalk doc §6a). Lower program_code only
    # when every twin is empty.
    def pick_twin(twins, flags)
      return [twins.first, false] if twins.size == 1

      chosen = twins.max_by { |p| [@enrollment.fetch(p.id, 0), -p.program_code.to_i] }
      counts = twins.sort_by(&:program_code).map { |p| "#{p.program_code}:#{@enrollment.fetch(p.id, 0)}" }
      flags << "program #{chosen.program_code} assumed among twins #{counts.join(', ')} " \
               "(majority enrollment) — verify"
      [chosen, true]
    end
  end
end
```

- [ ] **Step 2: Verify against known cases** — Run:
```bash
ruby -c app/services/chulabooster/program_resolver.rb
bin/rails runner '
r = Chulabooster::ProgramResolver.new
a = r.resolve(major_code: "21101", student_id: "6470000021", admission_year_be: 2567)   # CS, clean
b = r.resolve(major_code: "21100", student_id: "6070106021", admission_year_be: 2560)   # CM via segment 70
c = r.resolve(major_code: "21100", student_id: "3971081121", admission_year_be: 2539)   # seg 71 but pre-CD -> fallback to CM
d = r.resolve(major_code: "21103", student_id: "4931802021", admission_year_be: 2549)   # unresolvable
e = r.resolve(major_code: "21100", student_id: "4012345",    admission_year_be: 2540)   # 7-digit -> CP (twin year 2539: 0928 majority)
puts [a.group, a.program.program_code, a.failure.inspect].join(" ")
puts [b.group, b.program.program_code, b.heuristic].join(" ")
puts [c.group, c.program.program_code, c.flags.size].join(" ")
puts d.failure
puts [e.group, e.program.program_code, e.twin_tie].join(" ")
'
```
Expected output (5 lines): `CS 4242 nil` · `CM 2694 true` (2558 twins 2694:42/2695:7 → majority 2694) · `CM 0037 2` (seg 71 → CD, but no CD program by 2539 → falls back to **CM** per FALLBACK_ORDER — matches the two confirmed-CM students; 2 flags = heuristic + fallback) · `unmapped major_code "21103"` · `CP 0928 true` (0928 — the 604-student twin — proving majority-enrollment, NOT 0570).

- [ ] **Step 3: Commit**
```bash
hg commit app/services/chulabooster/program_resolver.rb \
  -m "Resolve CB students to local programs without trusting coarse CB identifiers

CB's student rows carry only a shared major_code (21100 covers bachelor,
master AND doctoral) and no usable program reference, so assignment needs
the validated student_id-segment heuristic, a year-existence fallback, and
a majority-enrollment default for twin-track ties — every assumption
surfaced as a flag for the student's remark, never silent.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `Chulabooster::StudentSync`

**Files:**
- Create: `app/services/chulabooster/student_sync.rb`

**Interfaces:**
- Consumes: `Client`/`SnapshotClient#each_row("students")`; `ProgramResolver#resolve(...) → Result`; `StatusCodes.to_local(code)`.
- Produces: `Chulabooster::StudentSync.new(client:, run_dir:, commit: false)#call → Hash` of counts with keys `:matched, :cb_only, :creatable, :created, :unresolved, :errors, :unknown_status, :heuristic_flagged, :twin_flagged, :program_discrepancies, :status_discrepancies, :stale_active`. Writes 6 CSVs into `run_dir`: `created_students.csv`, `unresolved_students.csv`, `row_errors.csv`, `students_program_discrepancies.csv`, `students_status_discrepancies.csv`, `unknown_status_codes.csv`. Used by Task 7.

- [ ] **Step 1: Write the class** (complete file):

```ruby
require "csv"
require "fileutils"

module Chulabooster
  # Phase 2a write path: creates local Student records for CB-only students and
  # writes report-only discrepancy CSVs for matched students. The ONLY database
  # writes are (a) new Student rows and (b) the mirror column cb_status_code on
  # matched students — both gated behind commit: true. Dry-run (the default)
  # computes everything and writes files only.
  # Policy: docs/chulabooster-program-crosswalk.md, docs/chulabooster-student-status-crosswalk.md.
  class StudentSync
    def initialize(client:, run_dir:, commit: false)
      @client = client
      @run_dir = run_dir
      @commit = commit
      FileUtils.mkdir_p(@run_dir)
    end

    def call
      resolver = ProgramResolver.new
      local_by_sid = Student.includes(program: :program_group).index_by { |s| s.student_id.to_s }
      counts = Hash.new(0)
      rows = { created: [], unresolved: [], errors: [], prog_disc: [], status_disc: [], unknown_code: [] }

      @client.each_row("students") do |row|
        local = local_by_sid[row["student_id"].to_s]
        if local
          check_matched(local, row, resolver, counts, rows)
        else
          create_missing(row, resolver, counts, rows)
        end
      end

      write_csv("created_students.csv",
                %w[student_id name program_code group status flags], rows[:created])
      write_csv("unresolved_students.csv",
                %w[student_id major_code admission_year_be reason], rows[:unresolved])
      write_csv("row_errors.csv", %w[student_id errors], rows[:errors])
      write_csv("students_program_discrepancies.csv",
                %w[student_id local_group cb_implied_group flags], rows[:prog_disc])
      write_csv("students_status_discrepancies.csv",
                %w[student_id local_status cb_status_code cb_implied_status], rows[:status_disc])
      write_csv("unknown_status_codes.csv", %w[student_id cb_status_code], rows[:unknown_code])
      counts
    end

    private

    def create_missing(row, resolver, counts, rows)
      counts[:cb_only] += 1
      sid = row["student_id"].to_s
      admission_year_be = row["start_academic_year"].to_i + 543

      if row["start_academic_year"].to_s.strip.empty?
        counts[:unresolved] += 1
        rows[:unresolved] << [sid, row["major_code"], nil, "missing start_academic_year"]
        return
      end

      result = resolver.resolve(major_code: row["major_code"], student_id: sid,
                                admission_year_be: admission_year_be)
      if result.failure
        counts[:unresolved] += 1
        rows[:unresolved] << [sid, row["major_code"], admission_year_be, result.failure]
        return
      end

      status = StatusCodes.to_local(row["student_status"])
      if status.nil?
        counts[:unknown_status] += 1
        rows[:unknown_code] << [sid, row["student_status"]]
        status = "unknown"
      end

      student = Student.new(
        student_id: sid,
        first_name: row["firstname"].to_s.strip,
        last_name: row["lastname"].to_s.strip,
        first_name_th: row["firstname_alt"].to_s.strip,
        last_name_th: row["lastname_alt"].to_s.strip,
        sex: row["gender"].presence,
        admission_year_be: admission_year_be,
        program: result.program,
        status: status,
        cb_status_code: row["student_status"].to_s
      )
      if result.flags.any?
        student.remark = "ChulaBooster sync #{Date.current}: #{result.flags.join('; ')}"
      end

      ok = @commit ? student.save : student.valid?
      unless ok
        counts[:errors] += 1
        rows[:errors] << [sid, student.errors.full_messages.join("; ")]
        return
      end

      counts[@commit ? :created : :creatable] += 1
      counts[:heuristic_flagged] += 1 if result.heuristic
      counts[:twin_flagged] += 1 if result.twin_tie
      rows[:created] << [sid, "#{student.first_name} #{student.last_name}",
                         result.program.program_code, result.group, status,
                         result.flags.join("; ")]
    end

    def check_matched(local, row, resolver, counts, rows)
      counts[:matched] += 1

      # Program identity: group-level comparison, report-only (local is authoritative).
      admission_year_be = row["start_academic_year"].to_i + 543
      result = resolver.resolve(major_code: row["major_code"], student_id: local.student_id.to_s,
                                admission_year_be: admission_year_be)
      local_group = local.program&.program_group&.code
      implied_group = result.failure ? nil : result.group
      if implied_group && local_group && implied_group != local_group
        counts[:program_discrepancies] += 1
        rows[:prog_disc] << [local.student_id, local_group, implied_group, result.flags.join("; ")]
      end

      # Status: CB is the more reliable source here, but still report-only.
      code = row["student_status"].to_s
      implied_status = StatusCodes.to_local(code)
      if implied_status && implied_status != local.status
        counts[:status_discrepancies] += 1
        counts[:stale_active] += 1 if local.status == "active"
        rows[:status_disc] << [local.student_id, local.status, code, implied_status]
      end

      # The one permitted write on existing records: mirror CB's raw code.
      if @commit && local.cb_status_code != code
        local.update_column(:cb_status_code, code)
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

- [ ] **Step 2: Syntax + load check** — Run: `ruby -c app/services/chulabooster/student_sync.rb && bin/rails runner 'Chulabooster::StudentSync; puts "loads"'`. Expected: `Syntax OK` / `loads`.
- [ ] **Step 3: Commit**
```bash
hg commit app/services/chulabooster/student_sync.rb \
  -m "Bring in the students only ChulaBooster knows about, without touching ours

The reconciliation dry-run found 1,441 students CB has that we never
imported. This first write path is deliberately narrow: create those
records (dry-run by default), flag every resolution assumption in the
student's remark, and only ever REPORT program/status disagreements on
existing students — the confirmed CM/CD false positives are standing proof
that CB's coarser signals must never overwrite local data.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Rake task `chulabooster:sync_students`

**Files:**
- Modify: `lib/tasks/chulabooster.rake` (append inside the existing `namespace :chulabooster`)

**Interfaces:**
- Consumes: `StudentSync.new(client:, run_dir:, commit:)#call → Hash` (Task 6 keys).

- [ ] **Step 1: Append the task** inside `namespace :chulabooster do ... end`, after the `reconcile` task:

```ruby
  desc "Create local Students for CB-only students + report discrepancies. DRY-RUN by default; " \
       "COMMIT=1 to write. SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts> to run offline."
  task sync_students: :environment do
    $stdout.sync = true

    run_dir = Rails.root.join("tmp", "chulabooster_sync", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    client  = ENV["SNAPSHOT_DIR"] ? Chulabooster::SnapshotClient.new(ENV["SNAPSHOT_DIR"]) : Chulabooster::Client.new
    commit  = ENV["COMMIT"] == "1"

    puts commit ? "MODE: COMMIT — new students WILL be created" : "MODE: dry-run — no database writes"
    counts = Chulabooster::StudentSync.new(client: client, run_dir: run_dir, commit: commit).call

    puts
    puts "matched:                #{counts[:matched]}"
    puts "cb_only:                #{counts[:cb_only]}"
    puts "#{commit ? 'created:               ' : 'creatable:             '} #{counts[commit ? :created : :creatable]}"
    puts "  heuristic-flagged:    #{counts[:heuristic_flagged]}"
    puts "  twin-flagged:         #{counts[:twin_flagged]}"
    puts "unresolved (skipped):   #{counts[:unresolved]}"
    puts "row errors:             #{counts[:errors]}"
    puts "unknown status codes:   #{counts[:unknown_status]}"
    puts "program discrepancies:  #{counts[:program_discrepancies]}   <- review students_program_discrepancies.csv"
    puts "status discrepancies:   #{counts[:status_discrepancies]} (#{counts[:stale_active]} locally-active look stale)"
    puts "\n→ reports: #{run_dir}"
  end
```

- [ ] **Step 2: Verify it loads** — Run: `bin/rails -T 2>/dev/null | grep sync_students`. Expected: the task listed with its description.
- [ ] **Step 3: Commit**
```bash
hg commit lib/tasks/chulabooster.rake \
  -m "Expose the student sync as a preview-first console task

First-ever CB write path, run under personal-account creds — so the task
defaults to a full dry-run with report files, and only COMMIT=1 writes.
SNAPSHOT_DIR= reuses a cached pull instead of hitting CB.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Acceptance run against the snapshot (the real test)

**Files:** none created (verification only). Requires `tmp/chulabooster_snapshot/full-2026-07-03` (regenerate via `bin/rails chulabooster:snapshot` if missing).

- [ ] **Step 1: Record row counts before** — Run:
```bash
bin/rails runner 'puts({ students: Student.count, programs: Program.count, grades: Grade.count }.inspect)'
```
Note the numbers (students expected 7181).

- [ ] **Step 2: Dry-run against the snapshot** — Run:
```bash
bin/rails chulabooster:sync_students SNAPSHOT_DIR=tmp/chulabooster_snapshot/full-2026-07-03
```
Expected summary — MUST match the design simulation exactly:
- `matched: 7135`, `cb_only: 1441`
- `creatable + row errors = 1432` (errors ≥ 1: student with blank lastname), `unresolved: 9`
- `heuristic-flagged: 506`, `twin-flagged: 328`
- `program discrepancies: 0` — the only two group-level disagreements in the data (the confirmed-CM pair `3971081121`/`3971235521`) are auto-resolved by the year-existence fallback, which was validated 146/146 exactly because of them. The report exists to catch FUTURE divergence.
- `stale_active: 765`, `unknown status codes: 0`

Any deviation = a resolution-logic bug. In particular, `program discrepancies: 2` means the FALLBACK_ORDER fix regressed (falling back to CP instead of CM). Investigate before proceeding (compare against `docs/chulabooster-program-crosswalk.md` §6c).

- [ ] **Step 3: Confirm the dry run wrote NOTHING** — Re-run the Step 1 command. Expected: identical counts. Also `hg status` shows no schema/db changes.

- [ ] **Step 4: Spot-check the reports** — Run:
```bash
ls tmp/chulabooster_sync/*/
grep -c "" tmp/chulabooster_sync/*/students_program_discrepancies.csv
grep -c "" tmp/chulabooster_sync/*/unresolved_students.csv
grep "3971081121\|3971235521" tmp/chulabooster_sync/*/students_program_discrepancies.csv || echo "confirmed-CM pair correctly absent"
```
Expected: 6 CSVs; program-discrepancy file has 1 line (header only — the confirmed-CM pair is correctly ABSENT because the fallback resolves them to CM); unresolved has 10 lines (header + 9 `21103` students).

- [ ] **Step 5: NO COMMIT=1 here.** Running the real write is the **user's decision** after reviewing the dry-run reports — the plan deliberately stops short of it.

---

### Task 9: Admin pointer page `/chulabooster`

**Files:**
- Create: `app/controllers/chulabooster_controller.rb`
- Create: `app/views/chulabooster/index.html.haml`
- Modify: `config/routes.rb` (one line), `app/helpers/application_helper.rb` (one hash entry), `app/views/layouts/application.html.haml` (one sidebar entry)

- [ ] **Step 1: Route** — in `config/routes.rb`, near `resources :scrapes`:
```ruby
  get "chulabooster", to: "chulabooster#index"
```

- [ ] **Step 2: Controller** (complete file — pattern copied from ScrapesController):
```ruby
class ChulaboosterController < ApplicationController
  before_action :require_admin

  def index
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
end
```

- [ ] **Step 3: View** (complete file — static card; deliberately no trigger button, console-first per spec):
```haml
.card
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        ChulaBooster Sync

    %p.text-body-secondary
      Syncs student records from ChulaBooster (the university registrar system). This is a
      console-first tool — it runs as a rake task on the server, previews everything as a
      dry-run first, and only writes when explicitly committed.

    %h6.mt-4 Commands
    %pre.p-3.rounded.border
      :plain
        bin/rails chulabooster:snapshot                  # cache a full CB pull (~40 min, resumable)
        bin/rails chulabooster:sync_students SNAPSHOT_DIR=tmp/chulabooster_snapshot/&lt;ts&gt;   # DRY-RUN (default)
        bin/rails chulabooster:sync_students SNAPSHOT_DIR=... COMMIT=1                     # create the students

    %p.mb-1
      The dry-run writes report CSVs (created / unresolved / discrepancies) under
      %code tmp/chulabooster_sync/&lt;timestamp&gt;/
      — review them before committing.

    %h6.mt-4 Background reading
    %ul
      %li
        %code docs/chulabooster-program-crosswalk.md
        — how CB program identifiers map to ours (and why assignment is flagged, not trusted)
      %li
        %code docs/chulabooster-student-status-crosswalk.md
        — why CB's status is more reliable than a stale local "active"
```

- [ ] **Step 4: Icon + sidebar** — in `app/helpers/application_helper.rb` add to `RESOURCE_ICONS` (before the closing `}.freeze`): `"chulabooster" => "sync",` . In `app/views/layouts/application.html.haml`, inside the `- if current_user.admin?` block after the Imports entry:
```haml
            %li.nav-item
              = link_to chulabooster_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'chulabooster'}" do
                = resource_icon("chulabooster")
                ChulaBooster
```

- [ ] **Step 5: Verify** — Run: `AUTO_LOGIN=1 bin/rails server -p 3009 -d && sleep 3 && curl -s http://localhost:3009/chulabooster | grep -o "ChulaBooster Sync" | head -1; kill $(cat tmp/pids/server.pid)`. Expected: `ChulaBooster Sync` (page renders; user ID 1 is the seeded admin).
- [ ] **Step 6: Commit**
```bash
hg commit app/controllers/chulabooster_controller.rb app/views/chulabooster/index.html.haml \
  config/routes.rb app/helpers/application_helper.rb app/views/layouts/application.html.haml \
  -m "Make the CB sync discoverable without making it self-service

Admins had no in-app trace that the ChulaBooster sync exists or how to run
it safely. A static pointer page documents the commands and the dry-run
policy; deliberately no trigger button while the integration runs under
personal-account credentials.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Documentation + STOP for user decisions

**Files:**
- Modify: `CLAUDE.md` (ChulaBooster Integration section)

- [ ] **Step 1: Add to CLAUDE.md** — in the "ChulaBooster Integration" section, append one bullet:
```markdown
- **Student sync (Phase 2a)**: `bin/rails chulabooster:sync_students` — dry-run by default,
  `COMMIT=1` to create CB-only students, `SNAPSHOT_DIR=` to run offline. Resolution logic:
  `Chulabooster::ProgramResolver` (major_code + student_id heuristic + majority-enrollment twin
  default, every assumption flagged in `remark`); status via `Chulabooster::StatusCodes`; raw CB
  code mirrored to `students.cb_status_code`. Report-only discrepancy CSVs for existing students.
  Admin pointer page at `/chulabooster`.
```
- [ ] **Step 2: Commit**
```bash
hg commit CLAUDE.md -m "Document the student sync entry points for future sessions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
- [ ] **Step 3: STOP — report to the user and ask two questions** (do not proceed on your own):
  1. **Tests** (per project convention): propose covering `StatusCodes` (family table + unknown), `ProgramResolver` (each branch: direct majors, segments 70/71/72/73, 7-digit, year-fallback, twin majority + empty-twin tiebreak, unresolvable), and a fixture-based `StudentSync` dry-run/commit pair asserting counts, CSV contents, and that dry-run performs zero writes. Ask whether to write them now.
  2. **The real run**: the dry-run reports from Task 8 are ready for review — ask whether to run `COMMIT=1` (and whether to `hg push`).
```
