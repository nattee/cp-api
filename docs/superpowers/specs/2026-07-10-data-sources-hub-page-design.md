# Data Sources hub page

**Status**: implemented 2026-07-10, revs 221–228 (plan: `docs/superpowers/plans/2026-07-10-data-sources-hub-page.md`). Tests (plan Task 6) deferred by the user.
**Date**: 2026-07-10

## Why

`/chulabooster` is an admin pointer page that explains how to run the ChulaBooster
sync. It exists because CB sync has no UI — it is console-only rake tasks, so a page
was the only place to record what to type and what to read first.

But CB is not our only external data provider. Schedule data comes from **CuGetReg**
and is cross-checked against **reg.chula**, and neither is mentioned anywhere a
reader would look. Meanwhile CSV/Excel upload — the other half of how data enters
this app — lives at `/data_imports` with no connection to the rest.

The result is that "how does data get into cp-api?" has no answer in the app. Worse,
the answers that *do* exist are scattered across `docs/`, and two of them are
expensive to rediscover:

- **CB cannot supply course offerings at all.** Not "not yet" — it exports five
  entities (`programs, courses, students, student_courses, program_courses`) and none
  of them is an offering. Its `courses` is catalog-only; `student_courses.section` is
  null in every one of its 49,502 rows. A session was spent establishing this.
- **reg.chula is not safe to import from.** It collapses a twice-weekly class into a
  single row with `day: "TU TH"`. `Scrapers::Base#parse_day` does a `DAY_MAP` lookup,
  gets `nil`, and hits `next if day.nil?` — the meeting is *silently dropped*. It also
  overwrites `Section` enrollment last-writer-wins.

This page turns that scattered, re-derivable knowledge into one place, and states each
source's limits as explicitly as its capabilities.

## Decisions

1. **Documentation hub, not a control panel.** The page explains every source and links
   out to the pages that already perform actions (`/scrapes`, `/data_imports`). CB's
   console commands stay inline because CB has no UI. `/scrapes` keeps its "New Scrape"
   form and its **Scraper** entry under *Teaching* — it is an operational tool for
   teaching staff, and moving it would be a regression.
2. **Covers all ingestion**, not just external providers: CSV/Excel imports,
   ChulaBooster, CuGetReg, reg.chula.
3. **Named "Data Sources" at `/data_sources`**, echoing CLAUDE.md's own phrasing
   ("imported via CSV/Excel and fetched from external data providers"). It reads as the
   umbrella over the existing **Imports** nav entry rather than a competing sibling.
4. **Data-driven.** A frozen `DataSource::SOURCES` constant drives one shared partial.
   Adding a fifth provider is a single hash entry, no view changes.
5. **Every source must state what it does *not* provide.** This is enforced by schema
   and by test, because it is the field that prevents wasted work.

## Architecture

### New files

- `app/models/data_source.rb` — a PORO (**not** ActiveRecord; there is no table).
  Holds the frozen `SOURCES` array and a `.find(key)` lookup. Single source of truth
  for page content.
- `app/controllers/data_sources_controller.rb` — carries `before_action :require_admin`
  over verbatim from `ChulaboosterController`; sets `@sources = DataSource::SOURCES`.
- `app/views/data_sources/index.html.haml` — index-page layout per `docs/code-patterns.md`
  (`.card` → `.card-body.p-3` → title row with `%h5.card-title`, no `.card-header`).
  Loops `@sources`.
- `app/views/data_sources/_source.html.haml` — renders one source.

### Changed files

- `config/routes.rb`

  ```ruby
  get "data_sources", to: "data_sources#index"
  get "chulabooster", to: redirect("/data_sources")   # keep old URL/bookmarks alive
  ```

- `app/helpers/application_helper.rb` — in `RESOURCE_ICONS`, replace
  `"chulabooster" => "sync"` with `"data_sources" => "database"`. Per-source icons live
  in `DataSource::SOURCES`, following the "domain icon mappings as frozen model
  constants" convention rather than overloading `RESOURCE_ICONS` (which maps
  *controllers* to icons).
- `app/views/layouts/application.html.haml` — in the Admin section, replace the
  **ChulaBooster** nav item with **Data Sources**, placed directly *above* **Imports**
  so the umbrella reads before the specific tool.
- `app/assets/stylesheets/application.scss` — four new frosted badge classes (below).
- `app/views/scrapes/index.html.haml` — relabel one dropdown option (below).

### Removed files

- `app/controllers/chulabooster_controller.rb`
- `app/views/chulabooster/index.html.haml`

Use `hg rename` where it preserves history (controller → controller, view → view).

## The `DataSource` schema

Every entry answers the same questions, so no source can quietly omit its limits.

```ruby
{
  key:          "cugetreg",        # stable identifier
  name:         "CuGetReg",
  icon:         "cloud_sync",      # Material Symbols
  badge:        "recommended",     # operating mode; class = "badge-#{badge.dasherize}"
  blurb:        "GraphQL API. The source of record for teaching schedules.",
  provides:     [ ... ],           # must be non-empty
  not_provides: [ ... ],           # must be non-empty
  caution:      nil,               # optional; rendered as a warning callout
  action:       { label: "Run a scrape", path: :scrapes_path },  # optional
  commands:     [ ... ],           # optional
  docs:         [ "docs/schedule-scraper.md" ]                   # optional
}
```

`action[:path]` stores a route-helper **symbol**, resolved in the view with `send`.
This keeps the constant free of request-time state.

`caution` renders in `_source.html.haml` as a Bootstrap `.alert.alert-warning` with a
`warning` Material Symbols icon; only reg.chula sets it today. Exact styling is settled
against the screenshot, not in this doc.

### Badges

Rendered data-driven as `"badge-#{src[:badge].dasherize}"`. Four new classes in
`application.scss`, following the existing frosted style (semi-transparent tinted
background, subtle border):

| Source        | `badge`         | class                  |
|---------------|-----------------|------------------------|
| Imports       | `manual_upload` | `.badge-manual-upload` |
| ChulaBooster  | `console_only`  | `.badge-console-only`  |
| CuGetReg      | `recommended`   | `.badge-recommended`   |
| reg.chula     | `verify_only`   | `.badge-verify-only`   |

The existing `.badge-manual` is **not** reused: it means `Grade#source == "manual"`
(hand-entered vs imported), a different domain concept. CLAUDE.md forbids reusing a
badge class with a different meaning.

## Content

### 1. CSV / Excel Imports — `upload_file`, `manual_upload`

- **Blurb**: Multi-step upload → column mapping → execute. Stays `pending` until you
  confirm the mapping; failed imports can be retried.
- **Provides**: any entity with an importer registered in `DataImport::IMPORTERS`.
- **Does not provide**: nothing automatic — one file per import, mapping confirmed by a
  human.
- **Action**: Go to Imports → `data_imports_path`.

### 2. ChulaBooster — `sync`, `console_only`

- **Blurb**: The university registrar system. Read-only client + reconciler. Every sync
  is dry-run by default and writes only with `COMMIT=1`.
- **Provides**: programs, courses, students, `student_courses` (grades), `program_courses`.
- **Does not provide**:
  - Course offerings, sections, time slots, rooms, teachers — CB has no such entity, and
    `student_courses.section` is null in every row.
  - Current-semester data — CB is populated after a term ends, so it lags roughly one
    semester.
- **Commands**: `chulabooster:snapshot`, then `sync_students` / `sync_courses` /
  `sync_grades` / `sync_program_courses`, with `SNAPSHOT_DIR=` and `COMMIT=1`.
  Dry-run report CSVs land under `tmp/chulabooster_sync/<timestamp>/` — review before
  committing.
- **Docs**: `docs/chulabooster-client-guide.md`,
  `docs/chulabooster-program-crosswalk.md`,
  `docs/chulabooster-student-status-crosswalk.md`.

### 3. CuGetReg — `cloud_sync`, `recommended`

- **Blurb**: GraphQL API. The source of record for teaching schedules.
- **Provides**: course offerings, sections, time slots, rooms, teacher initials,
  enrollment counts.
- **Does not provide**: grades, student records, program structure.
- **Action**: Run a scrape → `scrapes_path`.
- **Commands**: `bin/rails scraper:run SOURCE=cugetreg YEAR=2569 SEMESTER=2`
  (optional `PROGRAM=S|I`, `LIMIT=n`).
- **Docs**: `docs/schedule-scraper.md`.

### 4. reg.chula (CAS Reg) — `travel_explore`, `verify_only`

- **Blurb**: HTML scrape of `cas.reg.chula.ac.th`. A cross-check for CuGetReg, not an
  import source.
- **Provides**: the same shape as CuGetReg — offerings, sections, time slots.
- **Does not provide**: a safe import path.
- **Caution** (warning callout): *Do not import from this source.* It collapses a
  twice-weekly class into a single row with `day: "TU TH"`; `Scrapers::Base#parse_day`
  maps that to `nil` and `next if day.nil?` silently skips the slot, so meetings are
  lost. It also overwrites `Section` enrollment last-writer-wins. Use
  `Scrapers::CasReg.scrape` (read-only, non-`!`) to verify CuGetReg; never `scrape!`.
- **Docs**: `docs/schedule-scraper.md`.

## Adjacent fix: the `/scrapes` dropdown

Documenting "never import from reg.chula" while `/scrapes` offers a button that does
exactly that is a live contradiction. Minimal honest fix in
`app/views/scrapes/index.html.haml:22` — relabel the option:

```ruby
[["CuGetReg (recommended)", "cugetreg"],
 ["CAS Reg Chula (verify only — drops multi-day slots)", "cas_reg"]]
```

This preserves the escape hatch for anyone who knows what they are doing. Fixing
`parse_day` to split `"TU TH"` into two slots is the real repair, but it touches the
importer both scrapers share and needs its own testing — deliberately **out of scope**.

## Testing

To be confirmed before writing (per CLAUDE.md: discuss tests first; tests land after the
feature).

**Model** — `test/models/data_source_test.rb`

- every source has `key`, `name`, `icon`, `blurb`, `badge`
- `provides` and `not_provides` are both present and non-empty — enforces the contract
- `key` values are unique
- each `action[:path]` symbol resolves to a real route helper
- **each `docs:` path exists on disk** — stops documentation links rotting

**System** — `test/system/data_sources_test.rb`

- an admin sees all four source names and the reg.chula caution text
- a non-admin is redirected to root with the "Only admins" alert
- `/chulabooster` redirects to `/data_sources`

## Verification

Render `/data_sources` in headless Firefox and review the screenshot before sign-off —
this is a new UI surface, and styling is approved from rendered output, not markup.

## Out of scope

- Fixing `Scrapers::Base#parse_day` to handle multi-day rows.
- Moving the **Scraper** nav entry, or changing `/scrapes` beyond the one relabel.
- `docs/backlog.md` standing items: both trigger on *reports* and *entity show pages*.
  `/data_sources` is neither, so both are **consciously skipped**, not ignored.
