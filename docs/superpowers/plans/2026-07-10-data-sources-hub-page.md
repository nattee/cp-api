# Data Sources Hub Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ChulaBooster-only pointer page with `/data_sources`, an admin hub that documents all four ways data enters cp-api and states, for each, what it does *not* provide.

**Architecture:** A frozen `DataSource::SOURCES` constant (a PORO, no database table) is the single source of truth for page content. `DataSourcesController#index` hands it to a view that loops one shared partial. Actions stay on the pages that already own them (`/scrapes`, `/data_imports`); the hub only links out. CB's console commands render inline because CB has no UI.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, HAML, Bootstrap 5.3 (vendored SCSS), Dart Sass, Material Symbols, Minitest + fixtures, Capybara + Selenium + headless Firefox.

**Spec:** `docs/superpowers/specs/2026-07-10-data-sources-hub-page-design.md`

## Global Constraints

- **Version control is Mercurial (`hg`), not git.** There is no `.git` directory. Never run `git`.
- **Always name explicit files in `hg commit`.** This repo carries unrelated dirty changes (`app/models/staff.rb`, `lib/tasks/chulabooster.rake`, and others). A bare `hg commit` would sweep them in.
- **Commit messages lead with WHY.** First paragraph explains the problem/motivation; bullets cover what changed. The diff already shows the what.
- **No TDD on tasks 1–5.** CLAUDE.md states: *"After implementing a feature: ask whether to write tests before proceeding"* and *"Before writing tests: briefly discuss what will be tested and get user input."* User instructions override this skill's red-green default. Tests are **Task 6**, and Task 6 is **gated on explicit user approval**. Tasks 1–5 each end in a manual verification step instead.
- **Badges must use a named semantic `.badge-*` class**, rendered data-driven (`"badge-#{value.dasherize}"`). Never raw Bootstrap `bg-*`.
- **Never reuse an existing badge class with a different meaning.** `.badge-manual` already means `Grade#source == "manual"`.
- **Intranet-only.** No CDN links, no external URLs in served pages.
- **Material Symbols inline with text need `vertical-align: middle`** (see `docs/material-symbols-vertical-align.md`).
- **Turbo Drive is on globally.** Never use `DOMContentLoaded`. (This plan adds no JS.)
- **After changing SCSS, run `bin/rails dartsass:build`** — Propshaft does no compilation.
- `docs/backlog.md` standing items trigger on *reports* and *entity show pages*. `/data_sources` is neither. **Consciously skipped**, per the spec's Out of Scope section.

## File Structure

| File | Responsibility |
|---|---|
| `app/models/data_source.rb` | **Create.** Frozen `SOURCES` content constant + `.all` / `.find`. No DB. |
| `app/assets/stylesheets/application.scss` | **Modify.** Four new frosted operating-mode badge classes. |
| `app/controllers/data_sources_controller.rb` | **Create** (via `hg rename`). Admin gate + assigns `@sources`. |
| `app/views/data_sources/index.html.haml` | **Create** (via `hg rename`). Card shell, loops sources. |
| `app/views/data_sources/_source.html.haml` | **Create.** Renders exactly one source. |
| `config/routes.rb:31` | **Modify.** New route + redirect from the old one. |
| `app/helpers/application_helper.rb:23` | **Modify.** `RESOURCE_ICONS` key swap. |
| `app/views/layouts/application.html.haml:110-117` | **Modify.** Nav: Data Sources above Imports; drop ChulaBooster. |
| `app/views/scrapes/index.html.haml:22` | **Modify.** Relabel the `cas_reg` dropdown option. |
| `test/models/data_source_test.rb` | **Create** (Task 6, gated). Schema + doc-link integrity. |
| `test/system/data_sources_test.rb` | **Create** (Task 6, gated). Rendering, redirect, admin gate. |
| `app/controllers/chulabooster_controller.rb` | **Delete** (renamed away). |
| `app/views/chulabooster/index.html.haml` | **Delete** (renamed away). |

---

### Task 1: The `DataSource` content constant

The whole page is data. Get the data right first; everything downstream just renders it.

**Files:**
- Create: `app/models/data_source.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `DataSource::SOURCES` — a frozen `Array<Hash>`. Each hash has keys
  `:key` (String), `:name` (String), `:icon` (String, Material Symbols name),
  `:badge` (String, snake_case), `:blurb` (String), `:provides` (Array<String>, non-empty),
  `:not_provides` (Array<String>, non-empty), `:caution` (String or nil),
  `:action` (`{label: String, path: Symbol}` or nil), `:commands` (Array<String>),
  `:docs` (Array<String>, repo-relative paths).
  Also `DataSource.all` → `SOURCES`, and `DataSource.find(key)` → Hash or nil.

- [ ] **Step 1: Create the model**

Create `app/models/data_source.rb`:

```ruby
# Describes every path by which data enters cp-api.
#
# This is a PORO, not an ActiveRecord model — there is no data_sources table. It is
# the single source of truth for the /data_sources page.
#
# Each entry MUST state both what the source provides and what it does NOT provide.
# `not_provides` is the reason this page exists: the two facts recorded below each
# cost a full working session to rediscover.
class DataSource
  SOURCES = [
    {
      key: "imports",
      name: "CSV / Excel Imports",
      icon: "upload_file",
      badge: "manual_upload",
      blurb: "Multi-step upload, then column mapping, then execute. An import stays pending " \
             "until you confirm the mapping; failed imports can be retried.",
      provides: [
        "Any entity with an importer registered in DataImport::IMPORTERS"
      ],
      not_provides: [
        "Nothing automatic — one file per import, with the column mapping confirmed by a human"
      ],
      caution: nil,
      action: { label: "Go to Imports", path: :data_imports_path },
      commands: [],
      docs: []
    },
    {
      key: "chulabooster",
      name: "ChulaBooster",
      icon: "sync",
      badge: "console_only",
      blurb: "The university registrar system. A read-only client plus reconciler: every sync " \
             "is a dry-run by default and writes only with COMMIT=1.",
      provides: [
        "Programs, courses, and students",
        "Grades (CB calls these student_courses)",
        "Program-to-course pairings"
      ],
      not_provides: [
        "Course offerings, sections, time slots, rooms, teachers — CB has no such entity, " \
        "and student_courses.section is null in every row",
        "Current-semester data — CB is populated after a term ends, so it lags roughly one semester"
      ],
      caution: nil,
      action: nil,
      commands: [
        "bin/rails chulabooster:snapshot                       # cache a full CB pull (~40 min, resumable)",
        "bin/rails chulabooster:sync_students SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts>   # DRY-RUN (default)",
        "bin/rails chulabooster:sync_students SNAPSHOT_DIR=... COMMIT=1                     # actually write",
        "bin/rails chulabooster:sync_courses / sync_grades / sync_program_courses",
        "",
        "# Dry-run report CSVs land in tmp/chulabooster_sync/<timestamp>/ — review before committing."
      ],
      docs: [
        "docs/chulabooster-client-guide.md",
        "docs/chulabooster-program-crosswalk.md",
        "docs/chulabooster-student-status-crosswalk.md"
      ]
    },
    {
      key: "cugetreg",
      name: "CuGetReg",
      icon: "cloud_sync",
      badge: "recommended",
      blurb: "GraphQL API. The source of record for teaching schedules.",
      provides: [
        "Course offerings, sections, and time slots",
        "Rooms and teacher initials",
        "Enrollment counts (current / max)"
      ],
      not_provides: [
        "Grades and student records",
        "Program structure"
      ],
      caution: nil,
      action: { label: "Run a scrape", path: :scrapes_path },
      commands: [
        "bin/rails scraper:run SOURCE=cugetreg YEAR=2569 SEMESTER=2",
        "# optional: PROGRAM=S|I (default S), LIMIT=n to smoke-test first"
      ],
      docs: ["docs/schedule-scraper.md"]
    },
    {
      key: "cas_reg",
      name: "reg.chula (CAS Reg)",
      icon: "travel_explore",
      badge: "verify_only",
      blurb: "HTML scrape of cas.reg.chula.ac.th. A cross-check for CuGetReg — not an import source.",
      provides: [
        "The same shape as CuGetReg: offerings, sections, and time slots"
      ],
      not_provides: [
        "A safe import path — see the warning below"
      ],
      caution: "Do not import from this source. It collapses a twice-weekly class into a single " \
               'row with day: "TU TH". Scrapers::Base#parse_day looks that up in DAY_MAP, gets nil, ' \
               "and `next if day.nil?` silently skips the slot — the meeting is lost. It also " \
               "overwrites Section enrollment last-writer-wins. Use Scrapers::CasReg.scrape " \
               "(read-only) to verify CuGetReg; never scrape! .",
      action: nil,
      commands: [
        %q{bin/rails runner 'pp Scrapers::CasReg.scrape("2110200", 2569, 1)'   # read-only cross-check}
      ],
      docs: ["docs/schedule-scraper.md"]
    }
  ].freeze

  def self.all
    SOURCES
  end

  def self.find(key)
    SOURCES.find { |source| source[:key] == key }
  end
end
```

- [ ] **Step 2: Verify it loads and every doc path is real**

Run:

```bash
bin/rails runner '
  puts "sources: #{DataSource::SOURCES.size}"
  DataSource::SOURCES.each do |s|
    raise "#{s[:key]}: empty provides"     if s[:provides].empty?
    raise "#{s[:key]}: empty not_provides" if s[:not_provides].empty?
    s[:docs].each { |d| raise "#{s[:key]}: missing doc #{d}" unless Rails.root.join(d).exist? }
  end
  puts "find(cugetreg) => #{DataSource.find("cugetreg")[:name]}"
  puts "find(nope)     => #{DataSource.find("nope").inspect}"
  puts "OK"
'
```

Expected output:

```
sources: 4
find(cugetreg) => CuGetReg
find(nope)     => nil
OK
```

- [ ] **Step 3: Commit**

```bash
hg add app/models/data_source.rb
hg commit app/models/data_source.rb -m "Record how data enters cp-api, because the app never said

Nothing in the app names CuGetReg or reg.chula, and the two most expensive facts
about our data sources lived only in docs/ and in one engineer's head: CB cannot
supply course offerings at all (no such entity; student_courses.section is null in
every row), and reg.chula must never be imported from (it collapses twice-weekly
classes into a 'TU TH' row that parse_day silently drops).

- add DataSource PORO holding all four ingestion paths as a frozen constant
- every source must declare not_provides, not just provides
- no table: this is content, not state"
```

---

### Task 2: Operating-mode badge classes

The partial in Task 3 renders `badge-#{badge.dasherize}`. Define the classes first so the page is never styled-wrong on screen.

**Files:**
- Modify: `app/assets/stylesheets/application.scss` (insert after `.badge-course-group`, currently line 257)

**Interfaces:**
- Consumes: `:badge` values from `DataSource::SOURCES` — `manual_upload`, `console_only`, `recommended`, `verify_only`.
- Produces: CSS classes `.badge-manual-upload`, `.badge-console-only`, `.badge-recommended`, `.badge-verify-only`.

- [ ] **Step 1: Add the classes**

In `app/assets/stylesheets/application.scss`, find this line (≈257):

```scss
.badge-course-group { background-color: rgba($info, 0.12);             color: $info;    border: 1px solid rgba($info, 0.3); }
```

Insert immediately **after** it:

```scss

// Data-source operating-mode badges (/data_sources).
// These describe HOW you run a source, not what it contains.
// Deliberately NOT reusing .badge-manual — that means Grade#source == "manual"
// (hand-entered vs imported), a different domain concept.
.badge-manual-upload { background-color: rgba(150, 150, 150, 0.18); color: rgba(210, 210, 210, 0.8); border: 1px solid rgba(150, 150, 150, 0.35); }
.badge-console-only  { background-color: rgba($secondary, 0.2);     color: $secondary; border: 1px solid rgba($secondary, 0.4); }
.badge-recommended   { background-color: rgba($success, 0.2);       color: $success;   border: 1px solid rgba($success, 0.4); }
.badge-verify-only   { background-color: rgba($warning, 0.2);       color: $warning;   border: 1px solid rgba($warning, 0.4); }
```

- [ ] **Step 2: Compile and confirm the classes reach the build**

Run:

```bash
bin/rails dartsass:build && grep -c "badge-verify-only\|badge-recommended\|badge-console-only\|badge-manual-upload" app/assets/builds/application.css
```

Expected: compiles without error, and `grep -c` prints `4`.

- [ ] **Step 3: Commit**

```bash
hg commit app/assets/stylesheets/application.scss -m "Give data sources a badge for how you run them, not what they hold

A reader scanning /data_sources needs to know at a glance that CuGetReg is the one
to reach for and reg.chula is for verification only. Existing badges all describe
record contents; none describes an operating mode.

- add .badge-manual-upload / .badge-console-only / .badge-recommended / .badge-verify-only
- do NOT reuse .badge-manual: it already means Grade#source == 'manual'"
```

Note: `app/assets/builds/application.css` is a build artifact — do **not** add it to the commit unless `hg status` shows it is already tracked in this repo.

---

### Task 3: Controller, routes, and views

**Files:**
- Rename: `app/controllers/chulabooster_controller.rb` → `app/controllers/data_sources_controller.rb`
- Rename: `app/views/chulabooster/index.html.haml` → `app/views/data_sources/index.html.haml`
- Create: `app/views/data_sources/_source.html.haml`
- Modify: `config/routes.rb:31`

**Interfaces:**
- Consumes: `DataSource::SOURCES` (Task 1); badge classes (Task 2).
- Produces: route helper `data_sources_path` → `/data_sources`; `@sources` in the view; a `/chulabooster` → `/data_sources` redirect.

- [ ] **Step 1: Rename the files so history follows them**

```bash
hg rename app/controllers/chulabooster_controller.rb app/controllers/data_sources_controller.rb
mkdir -p app/views/data_sources
hg rename app/views/chulabooster/index.html.haml app/views/data_sources/index.html.haml
```

- [ ] **Step 2: Rewrite the controller**

Replace the entire contents of `app/controllers/data_sources_controller.rb` with:

```ruby
class DataSourcesController < ApplicationController
  before_action :require_admin

  def index
    @sources = DataSource::SOURCES
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
end
```

The alert string is copied verbatim from the old `ChulaboosterController` — the system test in Task 6 asserts on it.

- [ ] **Step 3: Rewrite the index view**

Replace the entire contents of `app/views/data_sources/index.html.haml` with:

```haml
.card
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Data Sources

    %p.text-body-secondary
      How data enters cp-api. Each source lists what it provides and, just as importantly,
      what it does not — check the second column before assuming a source can answer your question.

    - @sources.each_with_index do |src, index|
      = render "source", src: src, last: (index == @sources.size - 1)
```

- [ ] **Step 4: Create the source partial**

Create `app/views/data_sources/_source.html.haml`:

```haml
- wrapper_class = last ? "mb-0" : "mb-4 pb-4 border-bottom"
%div{class: wrapper_class}
  %h6.d-flex.align-items-center.mb-2
    %span.material-symbols.me-2{style: "font-size: 20px; vertical-align: middle"}= src[:icon]
    = src[:name]
    %span.badge.ms-2{class: "badge-#{src[:badge].dasherize}"}= src[:badge].humanize

  %p.text-body-secondary.small= src[:blurb]

  .row.g-3
    .col-md-6
      .small.text-uppercase.text-body-secondary.fw-semibold.mb-1 Provides
      %ul.small.mb-0
        - src[:provides].each do |item|
          %li= item
    .col-md-6
      .small.text-uppercase.text-body-secondary.fw-semibold.mb-1 Does not provide
      %ul.small.mb-0
        - src[:not_provides].each do |item|
          %li= item

  - if src[:caution].present?
    .alert.alert-warning.d-flex.align-items-start.mt-3.mb-0.py-2.px-3.small
      %span.material-symbols.me-2{style: "font-size: 18px; vertical-align: middle"} warning
      %div= src[:caution]

  - if src[:action].present?
    .mt-3
      = link_to src[:action][:label], send(src[:action][:path]), class: "btn btn-primary btn-sm"

  - if src[:commands].any?
    .small.text-uppercase.text-body-secondary.fw-semibold.mt-3.mb-1 Commands
    %pre.p-3.rounded.border.small.mb-0= src[:commands].join("\n")

  - if src[:docs].any?
    .small.text-uppercase.text-body-secondary.fw-semibold.mt-3.mb-1 Background reading
    %ul.small.mb-0
      - src[:docs].each do |doc|
        %li
          %code= doc
```

HAML escapes `=` output, so `<ts>` in the CB commands renders literally and the `"TU TH"` quotes in the caution are safe. Do not use the `:plain` filter here.

- [ ] **Step 5: Update routes**

In `config/routes.rb`, replace line 31:

```ruby
  get "chulabooster", to: "chulabooster#index"
```

with:

```ruby
  get "data_sources", to: "data_sources#index"
  get "chulabooster", to: redirect("/data_sources")
```

The redirect keeps existing bookmarks and any links in `docs/` alive.

- [ ] **Step 6: Verify the page renders and the old URL redirects**

Start the server with the auth bypass documented in CLAUDE.md, then check both paths:

```bash
AUTO_LOGIN=1 bin/rails server -p 3001 &
sleep 6
echo "--- /data_sources ---"
curl -s http://localhost:3001/data_sources | grep -o "Data Sources\|CuGetReg\|reg.chula (CAS Reg)\|Do not import from this source\|CB has no such entity" | sort -u
echo "--- /chulabooster redirect ---"
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" http://localhost:3001/chulabooster
kill %1
```

Expected:

```
--- /data_sources ---
CB has no such entity
CuGetReg
Data Sources
Do not import from this source
reg.chula (CAS Reg)
--- /chulabooster redirect ---
301 -> http://localhost:3001/data_sources
```

- [ ] **Step 7: Commit**

```bash
hg add app/views/data_sources/_source.html.haml
hg commit app/controllers/data_sources_controller.rb app/controllers/chulabooster_controller.rb \
          app/views/data_sources/index.html.haml app/views/data_sources/_source.html.haml \
          app/views/chulabooster/index.html.haml config/routes.rb \
  -m "Promote the ChulaBooster page into a hub for every data source

/chulabooster only ever existed because CB sync has no UI — it was the sole place to
record what to type. But CB is one of four ways data reaches this app, and the other
three (CSV/Excel upload, CuGetReg, reg.chula) went unmentioned. 'How does data get in?'
had no answer anywhere in the app.

- rename /chulabooster -> /data_sources; the old URL 301s so bookmarks survive
- one shared partial renders a frozen DataSource::SOURCES, so a fifth provider is
  one hash entry and no view change
- actions stay where they already work: the hub links out to /scrapes and /imports
  rather than duplicating their forms"
```

---

### Task 4: Navigation and resource icon

**Files:**
- Modify: `app/helpers/application_helper.rb:23`
- Modify: `app/views/layouts/application.html.haml:110-117`

**Interfaces:**
- Consumes: `data_sources_path` (Task 3).
- Produces: a sidebar **Data Sources** entry; `resource_icon` resolving for `controller_name == "data_sources"`.

- [ ] **Step 1: Swap the resource icon key**

In `app/helpers/application_helper.rb`, inside `RESOURCE_ICONS`, replace:

```ruby
    "chulabooster"     => "sync",
```

with:

```ruby
    "data_sources"     => "database",
```

`RESOURCE_ICONS` maps *controller names* to icons; per-source icons live on `DataSource::SOURCES` instead, following the "domain icon mappings as frozen model constants" convention.

- [ ] **Step 2: Rewrite the two nav items**

In `app/views/layouts/application.html.haml`, replace lines 110–117 — currently the **Imports** item followed by the **ChulaBooster** item:

```haml
            %li.nav-item
              = link_to data_imports_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'data_imports'}" do
                = resource_icon("data_imports")
                Imports
            %li.nav-item
              = link_to chulabooster_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'chulabooster'}" do
                = resource_icon("chulabooster")
                ChulaBooster
```

with the umbrella first, the specific tool second:

```haml
            %li.nav-item
              = link_to data_sources_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'data_sources'}" do
                = resource_icon("data_sources")
                Data Sources
            %li.nav-item
              = link_to data_imports_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'data_imports'}" do
                = resource_icon("data_imports")
                Imports
```

Note: Rails infers a named helper from the path string, so `chulabooster_path` **still exists** after Task 3 and now points at the redirect. Leaving the old nav item in place would therefore not crash — it would quietly send admins through a 301 to the very same page, under a label naming just one of its four sources. That silence is the reason to remove it deliberately rather than trust an error to catch it.

- [ ] **Step 3: Verify the nav renders and no stale helper survives**

```bash
grep -rn "chulabooster_path" app/ && echo "STALE REFERENCE FOUND — fix before continuing" || echo "no stale chulabooster_path references"

AUTO_LOGIN=1 bin/rails server -p 3001 &
sleep 6
curl -s http://localhost:3001/ | grep -o 'Data Sources\|>Imports<' | sort -u
kill %1
```

Expected: `no stale chulabooster_path references`, and the sidebar contains both `Data Sources` and `Imports`.

- [ ] **Step 4: Commit**

```bash
hg commit app/helpers/application_helper.rb app/views/layouts/application.html.haml \
  -m "Point the sidebar at the hub, above the tool it umbrellas

The Admin nav offered 'ChulaBooster' — one provider — as if it were a peer of
'Imports'. With the hub in place the entry should name the whole subject and sit
above the specific tool, so a reader meets the map before the territory.

- ChulaBooster nav item becomes Data Sources, placed above Imports
- RESOURCE_ICONS: chulabooster/sync -> data_sources/database
- chulabooster_path is gone; leaving the old item would NameError on every admin page"
```

---

### Task 5: Stop `/scrapes` inviting the import we just forbade

**Files:**
- Modify: `app/views/scrapes/index.html.haml:22`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. Copy change only; the `cas_reg` option value is unchanged, so `ScrapesController` and `ScheduleScrapeJob` are untouched.

- [ ] **Step 1: Relabel the dropdown option**

In `app/views/scrapes/index.html.haml`, replace line 22:

```haml
                = f.select "scrape[source]", options_for_select([["CuGetReg (recommended)", "cugetreg"], ["CAS Reg Chula", "cas_reg"]]), {}, class: "form-select form-select-sm"
```

with:

```haml
                = f.select "scrape[source]", options_for_select([["CuGetReg (recommended)", "cugetreg"], ["CAS Reg Chula (verify only — drops multi-day slots)", "cas_reg"]]), {}, class: "form-select form-select-sm"
```

Only the label changes. The submitted value stays `"cas_reg"`, preserving the escape hatch for anyone who knows what they are doing. Repairing `Scrapers::Base#parse_day` is explicitly out of scope — it touches the importer both scrapers share.

- [ ] **Step 2: Verify the option text and that the value is unchanged**

```bash
AUTO_LOGIN=1 bin/rails server -p 3001 &
sleep 6
curl -s http://localhost:3001/scrapes | grep -o '<option value="cas_reg">[^<]*</option>'
kill %1
```

Expected (em dash intact, value still `cas_reg`):

```
<option value="cas_reg">CAS Reg Chula (verify only — drops multi-day slots)</option>
```

- [ ] **Step 3: Commit**

```bash
hg commit app/views/scrapes/index.html.haml \
  -m "Stop the scrape form offering an import the docs forbid

/data_sources now states plainly that reg.chula must never be imported from: it
collapses a twice-weekly class into one 'TU TH' row that parse_day maps to nil and
silently skips, losing the meeting. Meanwhile this form listed 'CAS Reg Chula' as a
peer of CuGetReg, one click from doing exactly that.

- relabel the option to name the cost; the submitted value is unchanged, so the
  escape hatch survives for anyone who knows what they're doing
- fixing parse_day is the real repair, but it touches the shared importer and needs
  its own tests"
```

---

### Task 6: Tests — **GATED**

**STOP. Do not start this task without asking first.**

CLAUDE.md: *"After implementing a feature: ask whether to write tests before proceeding"* and *"Before writing tests: briefly discuss what will be tested and get user input."*

Ask the user, verbatim:

> Tasks 1–5 are done and `/data_sources` renders. I'd like to add two test files: a model test asserting every source declares both `provides` and `not_provides`, that keys are unique, that action paths resolve to real route helpers, and that **every cited `docs/` path exists on disk** (so links can't rot); and a system test covering admin rendering, the reg.chula caution text, the `/chulabooster` redirect, and the non-admin gate. Want me to write these, and is that the right coverage?

Only proceed on approval. If the user changes the coverage, adjust the steps below to match.

**Files:**
- Create: `test/models/data_source_test.rb`
- Create: `test/system/data_sources_test.rb`

**Interfaces:**
- Consumes: `DataSource` (Task 1), `data_sources_path` (Task 3), `users(:admin)` / `users(:viewer)` fixtures.
- Produces: nothing.

- [ ] **Step 1: Write the model test**

Create `test/models/data_source_test.rb`:

```ruby
require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  test "every source declares the required identity fields" do
    DataSource::SOURCES.each do |src|
      %i[key name icon badge blurb].each do |field|
        assert src[field].present?, "#{src[:key].inspect}: #{field} must be present"
      end
    end
  end

  test "every source states both what it provides and what it does not" do
    DataSource::SOURCES.each do |src|
      assert src[:provides].present?,     "#{src[:key].inspect}: provides must be non-empty"
      assert src[:not_provides].present?, "#{src[:key].inspect}: not_provides must be non-empty"
    end
  end

  test "keys are unique" do
    keys = DataSource::SOURCES.map { |src| src[:key] }
    assert_equal keys.uniq, keys, "duplicate DataSource keys"
  end

  test "action paths resolve to real route helpers" do
    helpers = Rails.application.routes.url_helpers
    DataSource::SOURCES.filter_map { |src| src[:action] }.each do |action|
      assert helpers.respond_to?(action[:path]), "#{action[:path]} is not a route helper"
    end
  end

  test "every cited doc exists on disk" do
    DataSource::SOURCES.flat_map { |src| src[:docs] }.each do |doc|
      assert Rails.root.join(doc).exist?, "#{doc} is cited on /data_sources but does not exist"
    end
  end

  test "find returns the source for a key, nil otherwise" do
    assert_equal "CuGetReg", DataSource.find("cugetreg")[:name]
    assert_nil DataSource.find("no_such_source")
  end

  test "SOURCES is frozen" do
    assert DataSource::SOURCES.frozen?
  end
end
```

- [ ] **Step 2: Run the model test**

Run: `bin/rails test test/models/data_source_test.rb`
Expected: `7 runs, ... 0 failures, 0 errors`

- [ ] **Step 3: Write the system test**

Create `test/system/data_sources_test.rb`. The login and logout mechanics are copied from `test/system/data_imports_test.rb`:

```ruby
require "application_system_test_case"

class DataSourcesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "page lists every data source" do
    visit data_sources_path
    assert_text "CSV / Excel Imports"
    assert_text "ChulaBooster"
    assert_text "CuGetReg"
    assert_text "reg.chula (CAS Reg)"
  end

  test "reg.chula carries the do-not-import caution" do
    visit data_sources_path
    assert_text "Do not import from this source"
  end

  test "chulabooster states it has no course offering data" do
    visit data_sources_path
    assert_text "CB has no such entity"
  end

  test "sources link out to the pages that own the actions" do
    visit data_sources_path
    assert_link "Go to Imports", href: data_imports_path
    assert_link "Run a scrape", href: scrapes_path
  end

  test "the old chulabooster url redirects to data sources" do
    visit "/chulabooster"
    assert_current_path data_sources_path
  end

  test "sidebar shows Data Sources for an admin" do
    visit root_path
    assert_selector "nav a", text: "Data Sources"
  end

  test "a non-admin cannot access data sources" do
    click_on users(:admin).name
    page.execute_script("document.querySelector('button.dropdown-item').click()")
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit data_sources_path
    assert_text "Only admins can perform this action."
  end
end
```

- [ ] **Step 4: Run the system test**

Run: `bin/rails test:system test/system/data_sources_test.rb`
Expected: `7 runs, ... 0 failures, 0 errors`

If `assert_text "ChulaBooster"` fails, confirm Task 4 actually removed the ChulaBooster nav item — a stale nav entry would make the assertion pass for the wrong reason on other pages, and its absence is what this test relies on.

- [ ] **Step 5: Run the full suite to check nothing regressed**

The renamed controller and the removed `chulabooster_path` helper are the risk here.

Run: `bin/rails test && bin/rails test:system`
Expected: 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
hg add test/models/data_source_test.rb test/system/data_sources_test.rb
hg commit test/models/data_source_test.rb test/system/data_sources_test.rb \
  -m "Make the page's promises testable, especially the ones that rot

/data_sources is only useful while its content stays true. Two things decay
silently: a source can be added without stating what it does NOT provide (losing the
whole point of the page), and a cited doc can be renamed or deleted, leaving a dead
pointer nobody notices.

- model test asserts non-empty provides AND not_provides on every source, unique
  keys, resolvable route helpers, and that every cited docs/ path exists on disk
- system test covers admin rendering, the reg.chula caution, the outbound action
  links, the /chulabooster redirect, and the non-admin gate"
```

---

### Task 7: Rendered verification

Styling is approved from rendered output, not from markup.

**Files:** none — verification only.

- [ ] **Step 1: Build CSS and capture the page**

```bash
SHOT=/tmp/claude-1002/-home-dae-cp-api/screenshots
mkdir -p "$SHOT"
bin/rails dartsass:build
AUTO_LOGIN=1 bin/rails server -p 3001 &
sleep 6
firefox --headless --window-size=1500,2200 --screenshot "$SHOT/data_sources.png" "http://localhost:3001/data_sources"
firefox --headless --window-size=1500,1200 --screenshot "$SHOT/scrapes.png"      "http://localhost:3001/scrapes"
kill %1
ls -la "$SHOT"
```

- [ ] **Step 2: Read both screenshots and check them**

Use the Read tool on `data_sources.png` and `scrapes.png`. Confirm:

1. Four sources render, each with a badge, in order: Imports, ChulaBooster, CuGetReg, reg.chula.
2. All four badges are **styled** (tinted, bordered) — an unstyled badge means Task 2's SCSS did not reach the build.
3. The reg.chula caution renders as an amber alert with a warning icon, legible on the dark theme.
4. "Provides" and "Does not provide" sit side by side on a wide viewport.
5. The `<ts>` placeholder in the CB commands renders literally, not as a swallowed HTML tag.
6. The last source has no trailing border rule under it.
7. On `scrapes.png`, the Source dropdown shows the new `CAS Reg Chula (verify only …)` label.

- [ ] **Step 3: Show the screenshots to the user and get sign-off**

Present both images. Do not consider the work done until the user has seen the rendered page — this is a new UI surface, and the badge palette in particular (`$success` for recommended, `$warning` for verify-only) is a judgement call that should be checked against the real dark theme rather than assumed.

- [ ] **Step 4: Update the spec's status line**

In `docs/superpowers/specs/2026-07-10-data-sources-hub-page-design.md`, change:

```markdown
**Status**: design approved, not yet implemented
```

to:

```markdown
**Status**: implemented 2026-07-10 (see docs/superpowers/plans/2026-07-10-data-sources-hub-page.md)
```

Then:

```bash
hg commit docs/superpowers/specs/2026-07-10-data-sources-hub-page-design.md \
  -m "Mark the Data Sources hub design as implemented

A spec that still reads 'not yet implemented' after the fact sends the next reader
looking for work that is already done."
```

---

## Notes for the implementer

- **`hg`, never `git`.** And always list files explicitly on `hg commit` — this repo has unrelated dirty changes sitting in the working directory.
- **Do not "improve" `Scrapers::Base#parse_day`.** Its `"TU TH"` blind spot is real and is documented on the new page, but fixing it changes the importer both scrapers share and belongs in its own change with its own tests.
- **Do not move `/scrapes` or its nav entry.** It is an operational tool for teaching staff and stays under *Teaching*. The hub links to it; it is not absorbed.
- If a source's `not_provides` ever feels like it has nothing to say, that is a signal the entry is wrong, not that the field is unnecessary. Every source in this app has a limit worth naming.
