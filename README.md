# CP-API

Internal information system for the Department of Computer Engineering,
Chulalongkorn University. It keeps student records, curricula, course
offerings, teaching schedules, and grades in one place, and exposes them
through a web UI, a report hub, and a LINE chatbot. Data arrives via CSV/Excel
imports, a schedule scraper, and a sync against the university registrar
system (ChulaBooster). The app never writes back to any upstream system.

## What it does

- **Students, staff, programs, courses** — full CRUD with program revisions
  (`ProgramGroup` → `Program`), course revisions keyed by `course_no`,
  per-program curriculum groups, advisorships (history-preserving).
- **Teaching schedule** — semesters, course offerings, sections, time slots,
  rooms, and teaching assignments, with CSV import/export.
- **Grades** — per-student course history, grade distributions, GPA/GPAX.
- **Reports** — a permission-filtered hub at `/reports` (schedules, teaching
  load, grade distributions, cohort GPA, credit shortfalls, data coverage).
- **Data sources** — multi-step CSV/Excel import, a schedule scraper, a
  ChulaBooster reconciler + sync, and a one-off import of the department's
  30th-anniversary alumni directory. The admin page `/data_sources` documents
  what each source does and does not provide.
- **Roles & permissions** — a fixed permission catalog in code, roles as DB
  rows with inheritance, admin UI at `/roles`.
- **LINE bot** — account linking, slash commands, and an LLM chat that answers
  questions from the database through permission-checked tools. The same chat
  is available on the web at `/chat` (admin).

## Tech Stack

- Ruby 3.4.8, Rails 8.1
- MySQL 8.0 (user `cp_api`; databases `cp_api_development`, `cp_api_test`,
  `cp_api_production`)
- Solid Queue for background jobs (scrapes, imports)
- Propshaft (asset pipeline), Importmap (JS modules), Dart Sass (SCSS)
- HAML templates, Turbo, Stimulus
- Bootstrap 5.3 (vendored SCSS + JS), DataTables, Chart.js, Select2, Flatpickr

## Requirements

- **Intranet-only**: the app must work without public internet access. All
  CSS, JS, and font assets are vendored locally. No CDN links or external URLs
  in served pages.
- MySQL 8.0, Firefox ESR + geckodriver (system tests only), `mutool` from
  MuPDF (30-year book import only).

## Setup

```bash
bundle install
bin/rails db:create db:migrate db:seed
```

`db:seed` creates a super admin at user ID 1 (`root` / `password123`), the
seeded roles (`admin`, `staff`, `minimal`, `public_info`), a placeholder
program, and loads the staff/program seeds from `db/seeds/`.

Optional per-host configuration:

- `config/llm.yml` — LLM backends for the LINE/web chat. Copy from
  `config/llm.yml.example`; the real file is ignored by version control.
- Rails encrypted credentials (`bin/rails credentials:edit`) hold the LINE
  channel secret/token (`line:`) and the ChulaBooster API settings
  (`chulabooster:`). Both are optional; the rest of the app runs without them.

## Development

```bash
bin/dev                      # Rails server + dartsass:watch (via Foreman)
bin/rails server             # Rails server only (no SCSS recompilation)
AUTO_LOGIN=1 bin/dev         # Bypass login, auto-authenticate as user ID 1
```

`AUTO_LOGIN=<user id>` only takes effect in the development environment.
A style guide with a live color playground is at `/dev/styleguide`
(development only).

## Testing

```bash
bin/rails test               # Unit/model tests
bin/rails test:system        # System tests (headless Firefox)
bin/rails test test/system/foo_test.rb   # One system test file
bin/rails llm:eval           # LLM tool-selection accuracy (needs an LLM backend)
```

System tests drive Firefox via **geckodriver**, whose version must match the
installed Firefox or Selenium logs a compatibility warning (e.g. Firefox 151
needs geckodriver ≥ 0.37.0). selenium-webdriver's Selenium Manager
auto-provisions a matching driver **only when none is found on `PATH`** — if you
keep a geckodriver in `PATH`, you must bump it yourself when Firefox updates.

GitHub Actions (`.github/workflows/ci.yml`) runs Brakeman, bundler-audit,
importmap audit, RuboCop, and both test suites on pull requests.

## Roles & Permissions

Permissions are a fixed catalog in `Permission::CATALOG` (`courses.read`,
`students.read_minimal`, `students.read_full`, `grades.read`,
`advisees.read_full`, `users.manage`). Roles bundle permission keys and can
inherit from each other; they are managed at `/roles`. New users default to
`public_info`. Advisor access is data, not a role: `advisees.read_full` only
activates through `advisorships` rows. Check access with `user.can?("key")`.

## Data Sources

### CSV / Excel import

Multi-step flow at `/data_imports`: upload → column mapping (auto-detected
where possible, with fixed-value fallbacks) → execute. Failed imports can be
retried. Importers: **Student, Course, Grade, Schedule, Advisorship**
(`DataImport::IMPORTERS`). Year columns are Buddhist Era; importers convert
C.E. values automatically.

### Schedule scraper

Fetches course schedules from university registration websites.

```bash
bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=1   # rake
Scrapers::CuGetReg.scrape("2110327", 2568, 2)                 # console: fetch only
Scrapers::CuGetReg.scrape!("2110327", 2568, 2)                # console: fetch + import
```

Sources: `cugetreg` (GraphQL, recommended) and `cas_reg` (HTML scraping,
fallback). Admins trigger and monitor scrapes at `/scrapes`. Rate limits,
timeouts, and retries live in `config/scraper.yml`.

### ChulaBooster (registrar) sync

Read-only client + reconciler, with additive sync tasks. Every sync is a
**dry run by default**; pass `COMMIT=1` to write. `SNAPSHOT_DIR=` runs any
task offline against a snapshot.

```bash
bin/rails chulabooster:snapshot              # dump all CB entities to disk once
bin/rails chulabooster:reconcile             # report-only comparison
bin/rails chulabooster:sync_students         # create CB-only students
bin/rails chulabooster:sync_courses          # create CB-only courses
bin/rails chulabooster:sync_grades           # create CB-only grades, correct stale values
bin/rails chulabooster:correct_student_statuses  # apply CB-implied status to local students
bin/rails chulabooster:sync_program_courses  # link program↔course pairings
```

Local program assignments are authoritative and are never overwritten by CB.
See `docs/chulabooster-program-crosswalk.md` for the policy.

### 30-year book import

One-off import of the alumni directory printed in the department's
30th-anniversary book (`bin/rails book30:import`, `book30:rollback`,
`book30:report`; dry run by default, `COMMIT=1` to write). Results are on
`/data_sources/book30`; `/data_sources/provenance` shows where every student
row came from.

## LINE Bot & LLM Chat

- Webhook: `POST /line/webhook` (the only route meant to be reachable from
  outside the intranet, via a reverse proxy).
- Account linking: `/line_account` issues a token, the user sends
  `link <token>` in LINE. Admins can also onboard unlinked contacts from
  `/line_contacts`.
- Chat: free-text messages go to an OpenAI-compatible LLM backend
  (`config/llm.yml`) that queries the database through tools. Each tool
  declares a permission key and is filtered per user. Tool calls are persisted
  and inspectable at `/chat_messages` and `/api_events`.
- Adding a command: one file in `app/services/line/commands/` plus one entry
  in `MessageRouter::COMMAND_MAP`.

## Version Control

This project uses **Mercurial (hg)**. The GitHub repository is a mirror pushed
with `hg-git`; the `master` bookmark maps to the `master` branch.

Commit messages lead with **why** the change exists (the problem or
motivation), then what changed.

## Documentation

Design and reference docs live in `docs/`:

| File | Topic |
| --- | --- |
| `docs/code-patterns.md` | Canonical controller, view, fixture, and test templates |
| `docs/backlog.md` | Standing items with explicit re-check triggers |
| `docs/teaching-schedule.md` | Teaching schedule data model, CRUD, import/export |
| `docs/schedule-reports.md` | Schedule report views |
| `docs/schedule-scraper.md` | Scraper architecture and dev setup |
| `docs/line-integration.md` | LINE bot architecture, credentials, dev tunnel, tools |
| `docs/line-quick-link.md` | Admin-initiated LINE onboarding |
| `docs/llm-api.md` | Calling the self-hosted LLM backends directly |
| `docs/llm-data-query.md` | Original LLM data-query design (superseded, kept for history) |
| `docs/llm-eval-results.md` | Tool-selection eval results per model |
| `docs/llm-debugging-2026-04-04.md` | Chronological LLM debugging record |
| `docs/tool-chain-audit.md` | How tool calls are persisted, logged, and inspected |
| `docs/chulabooster-client-guide.md` | ChulaBooster API contract |
| `docs/chulabooster-program-crosswalk.md` | Program matching findings and sync policy |
| `docs/chulabooster-student-status-crosswalk.md` | Student status mapping findings |
| `docs/book30-import-report.md` | 30-year book import results and outcome vocabulary |
| `docs/data-provenance-report.md` | Where every student row came from |
| `docs/shadcn-color-mapping.md` | Theme palette and how to update it |
| `docs/bootstrap-table-border-bug.md` | Why `$table-border-color` does not work |
| `docs/material-symbols-vertical-align.md` | Inline icon alignment |
| `docs/superpowers/specs/` | Dated design specs for larger features |

`CLAUDE.md` holds the working conventions for the codebase (UI components,
data model rules, import system, deploy procedure).
