# ChulaBooster Reconciliation (Dry-Run) — Design

**Date:** 2026-07-01
**Status:** Approved design — pending implementation plan
**Project:** 2 (ChulaBooster sync), **Phase 1**. This is the read-only precursor to the authoritative sync; later phases (the actual write-back sync) are separate specs.

---

## Why (motivation)

Project 2 will make ChulaBooster the **authoritative** source for the entities it provides — meaning a sync
will *overwrite* managed fields in CP-API. Before enabling any write-back, we want a **read-only dry run**
that answers: *"what would the sync actually change against the data we already imported?"*

The reconciliation:
- **Previews the blast radius** — exactly which local records/fields an authoritative sync would overwrite,
  add, or leave orphaned.
- **Validates the mapping and crosswalks** against real data (CE→BE, `program_id→program_code`,
  `*_alt→Thai`, `course_id→course`), before we trust them in a writing sync.
- Is **self-diagnosing**: if a match-key encoding is wrong, the report shows near-zero matches for that
  entity — a visible signal, not a silent bug.

This was recorded as a required Phase 1 in the Course↔Program re-model spec
(`docs/superpowers/specs/2026-06-30-course-program-m2m-remodel-design.md`), and depends on that re-model
(the `ProgramCourse` join) already being in place.

## Scope

**In scope**
- A **read-only** reconciliation covering **all five** export entities (programs, courses, students,
  program_courses, student_courses), **full pull**.
- A reusable read-only API client, a reconciler with per-entity mappers, and a rake task orchestrator.
- Output: a **console summary** + **report files on disk** (Markdown summary + per-entity CSVs). No DB model.
- Resumability for the long `student_courses` pass.

**Out of scope** (later Project 2 phases)
- The actual **write-back sync** (any DB mutation from CB data).
- A persisted `ReconciliationRun` model / in-app web page (deliberately deferred — YAGNI for a pre-sync dry run).
- Scheduled/automated runs, delta (`changed_since`) sync cadence, unmapped-program placeholder policy.

## Decisions captured

| Decision | Choice | Rationale |
|---|---|---|
| Entity scope | **All 5, full pull** | Complete single picture; accept the long grades runtime (run it and wait / `nohup`). |
| Output | **Console summary + report files** | Durable, shareable, diffable; no model/UI build needed now. |
| Approach | **A — reusable client + reconciler + rake** | The read-only client is reused verbatim by the eventual sync; reconciler/rake sit on top. (Rejected: one inline rake script — not reusable, untestable; bending the write-oriented Importer/Scraper frameworks — wrong grain.) |

---

## Architecture

```
lib/tasks/chulabooster.rake  (reconcile)  →  Chulabooster::Reconciler  →  Chulabooster::Client (read-only HTTP)
                                                     │                              └─ GET /api/ext/export/*
                                                     ├─ per-entity mappers (crosswalks + field comparisons)
                                                     └─ Chulabooster::ReportWriter → tmp/reconciliation/<ts>/
```

Creds come from `Rails.application.credentials.chulabooster` (`base_url`, `app_id`, `app_secret`), already configured.

## Component 1 — `Chulabooster::Client` (read-only API client)

`app/services/chulabooster/client.rb`. The one piece the eventual sync reuses verbatim.

```ruby
module Chulabooster
  class Client
    EXPORT_ENTITIES = %w[programs courses students student_courses program_courses].freeze
    BASE_PATH   = "/api/ext/export"
    PAGE_SIZE   = 500          # max allowed; amortizes student_courses' ~26s/request
    RETRY_COUNT = 3
    RETRY_DELAY = 2            # seconds
    READ_TIMEOUT = 180         # must exceed the ~26s/request student_courses cost

    def initialize(config: Rails.application.credentials.chulabooster)
      @base_url, @app_id, @app_secret = config.fetch(:base_url), config.fetch(:app_id), config.fetch(:app_secret)
    end

    # Primitive: one page at a time, so the caller can checkpoint the cursor.
    #   each_page("students", changed_since: nil, start_cursor: nil) { |rows, next_cursor| ... }
    def each_page(entity, changed_since: nil, start_cursor: nil)
      validate!(entity)
      cursor = start_cursor
      loop do
        page = fetch_page(entity, cursor:, changed_since:)
        yield page.fetch(entity), page["next_cursor"]
        cursor = page["next_cursor"]
        break if cursor.nil?
      end
    end

    def each_row(entity, **opts, &blk) = each_page(entity, **opts) { |rows, _| rows.each(&blk) }

    private
    # fetch_page: Net::HTTP GET BASE_PATH/entity?limit=&cursor=&changed_since= with DeeAppId/DeeAppSecret
    #   headers; retry on Timeout/conn/5xx up to RETRY_COUNT (RETRY_DELAY apart); raise
    #   Chulabooster::AuthError (401) / PermissionError (403) / RequestError (other 4xx) — no retry;
    #   JSON.parse the body → { "count", entity => [...], "next_cursor" }.
    def validate!(entity) = EXPORT_ENTITIES.include?(entity) or raise ArgumentError, "unknown entity #{entity}"
  end
end
```

**Behaviors:** read-only by construction (only `GET` to `/api/ext/export/*`, entity validated against the
fixed allowlist); keyset pagination via `next_cursor` (per-page cursor is what enables resume); generous
read timeout for the slow endpoint; auth errors fail fast, transient errors retry.

## Component 2 — `Chulabooster::Reconciler` + per-entity mappers

`app/services/chulabooster/reconciler.rb` + `app/services/chulabooster/mappers/*`.

**Algorithm** (one streaming pass per entity; local held in memory):
```ruby
local = mapper.local_scope.index_by { |rec| mapper.local_key(rec) }
buckets = { identical: 0, changed: [], cb_only: [], local_only: [] }
seen = Set.new
client.each_page(mapper.entity, start_cursor:) do |rows, next_cursor|
  rows.each do |cb_row|
    key = mapper.cb_key(cb_row)            # applies crosswalks/conversions
    rec = local[key]
    if rec.nil?
      buckets[:cb_only] << key
    else
      seen << key
      diffs = mapper.field_diffs(rec, cb_row)      # [] if identical
      diffs.empty? ? buckets[:identical] += 1 : buckets[:changed] << { key:, diffs: }
    end
  end
  checkpoint(mapper.entity, next_cursor, seen)      # resumability (Component 4)
end
buckets[:local_only] = local.keys - seen.to_a
```

Each mapper declares `entity`, `local_scope`, `local_key`, `cb_key`, and the **CB-managed** fields to
compare. Local-only fields (`discord`, `line_id`, `guardian_*`, `remark`, …) are **never compared** — the
sync will not touch them (managed-vs-local policy).

| Entity | Match key | Compared (CB-managed) fields | Conversions |
|---|---|---|---|
| programs | `program_code ↔ CB program_id` | name_en, name_th, year_started, alternative_program_code | CB `revision_year` CE→BE; names via `program_group`; CB `program_code`→`alternative_program_code` |
| courses | `(course_no, revision_year BE)` | name, name_th, credits, l_credits, l_hours, nl_hours, s_hours, is_thesis, is_gened | CE→BE; `course_name`→name, `course_name_alt`→name_th, `gened`→is_gened |
| students | `student_id` | first_name, last_name, first_name_th, last_name_th, sex, admission_year_be, status | `firstname`/`lastname`→EN, `*_alt`→TH, `gender`→sex, `start_academic_year` CE→BE→admission_year_be, `national_id` **ignored** |
| program_courses | `(program_code, course_no, revision_year BE)` | membership present/absent | `program_id`→program_code; `course_id`→(course_no, rev); `course_group_code`/`course_type` are null locally → not compared |
| student_courses | `(student_id, course_no+rev BE, year BE, semester, section)` | grade, credits_grant | `course_id`→course, `academic_year` CE→BE, `semester_code`→semester |

**Crosswalks** (confirmed against live data during the Project-1 probes):
`program_id ↔ program_code`; CB `program_code`(6-digit) ↔ `alternative_program_code`; `*_alt` = Thai,
base = English; `course_id` = CE-year + `course_no` (resolve to local Course by `(course_no, revision_year BE)`);
years are CE → apply the importers' `+543` when value < 2400.

**Encoding-honesty stance** (deliberate, not a gap): `student_status`, `semester_code`, and `grade_type`
have encodings we have not confirmed. Fields with confirmed mappings (names, years, credits, grade letter)
are normalized and compared; the unconfirmed ones are compared **raw** and flagged `encoding-unverified` in
the report so a human interprets them. Because `semester_code`/`section` are part of the grades match key, a
wrong encoding shows up as a near-zero **matched** count for `student_courses` — a visible diagnostic.

## Component 3 — Report (`Chulabooster::ReportWriter`) and console output

`app/services/chulabooster/report_writer.rb`. No DB model.

**Console** — one row per entity:
```
entity            local    cb   matched  identical  changed  cb-only  local-only
programs             46   260        44         40        4      216           2
...
→ files: tmp/reconciliation/20260701-1840/
```
`matched` is the prominent safety signal (near-zero ⇒ key-encoding mismatch, not real drift).

**On disk** — `tmp/reconciliation/<timestamp>/`:
- `summary.md` — the table above + run metadata (time, CB host, per-entity `encoding-unverified` notes).
- Per entity, up to three CSVs: `<entity>_changed.csv` (columns: `key, field, local_value, cb_value, verified`),
  `<entity>_cb_only.csv`, `<entity>_local_only.csv`. Identical rows are counted only, never dumped.

## Component 4 — Read-only guarantee + resumability

`lib/tasks/chulabooster.rake` (`reconcile`). Mirrors the existing `scraper.rake` conventions
(`$stdout.sync`, ENV args, progress output).

**Read-only.** The client only issues `GET`s; the reconciler only *reads* the local DB and *writes files*
under `tmp/reconciliation/…`. No `save`/`create`/`update`/`destroy` anywhere in the path. A test asserts the
run leaves every model's row count unchanged.

**Resumable.** As it runs it **streams** result rows to the per-entity CSVs and appends matched keys to a
`<entity>_seen` file, then writes a small `checkpoint.json` (`{ entity, next_cursor }`) after **every page**.
Invocation:
- `bin/rails chulabooster:reconcile` — fresh run into a new timestamped dir.
- `RESUME=tmp/reconciliation/<ts> bin/rails chulabooster:reconcile` — skip completed entities, resume the
  in-progress entity from its saved `next_cursor`, reload `seen` from file, then compute `local_only` at
  entity completion.

Grades page at `limit=500` (Component 1) to amortize the ~26s/request cost; the full grades pass may run
tens of minutes to hours — run it with `nohup`/`screen` if needed.

## Component 5 — Testing

Minitest + fixtures, written after the build (confirm specifics first, per `CLAUDE.md`). The reconciler is
tested by feeding **hand-written CB rows** + **real local fixtures** — no live API.

- **Client** — stubbed HTTP: follows `next_cursor` across pages and stops at null; rejects unknown entities;
  raises clear errors on 401/403 and retries on timeouts; only issues `GET` to `/api/ext/export/*`.
- **Reconciler + mappers** — feed local fixtures + CB rows; assert one record lands in each bucket
  (identical / changed with the exact field diff / cb_only / local_only). Separate unit tests for the
  conversions: CE→BE, `program_id→program_code`, `*_alt→Thai`, `course_id→course`.
- **Read-only guard** — run a full reconcile against fixtures; assert every table's row count is unchanged.
- **Report writer** — given a result, assert `summary.md` + the per-entity CSVs have the expected columns/rows.
- **Resume** — given a saved checkpoint, assert the run skips completed entities and continues the
  in-progress one from its cursor.

## Open questions for later Project-2 phases (not this phase)

- Confirm the `student_status` / `semester_code` / `grade_type` encodings with the server team (the dry-run
  report will surface where they matter).
- Unmapped-program policy (CB programs with long 12-digit `program_id`s and no local `program_code`):
  skip / null / placeholder — decided when the write-back sync is designed.
- Whether to promote the file report into a persisted run + web page once the sync is live.
- Service-account provisioning (the key is currently bound to a personal account, `net.nattee`).
