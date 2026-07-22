# CP-API

Backend for the Department of Computer Engineering, Chulalongkorn University.
Read-only API for student information (info, classes, scores) with a frontend for viewing data.
Data is imported via CSV/Excel and fetched from external data providers.

## Backlog

`docs/backlog.md` holds recurring items with explicit triggers. **Whenever you add or
change a report or an entity show page, open it and check the triggered items**
(entity→report cross-links, report↔entity overlap review) — apply, extend, or
consciously skip them; never ignore silently.

## Tech Stack

- Ruby 3.4.8, Rails 8.1
- MySQL 8.0 (user: `cp_api`, databases: `cp_api_development`, `cp_api_test`, `cp_api_production`)
- Propshaft (asset pipeline), Importmap (JS modules), Dart Sass (SCSS compilation)
- HAML templates, Turbo, Stimulus
- Bootstrap 5.3 (vendored SCSS + JS), DataTables, Chart.js, Select2, Flatpickr

## Requirements

- **Intranet-only**: The app must work without public internet access. All CSS, JS, and font assets are vendored locally. No CDN links or external URLs in served pages.

## Asset Pipeline

- **CSS**: Dart Sass compiles `app/assets/stylesheets/application.scss` → `app/assets/builds/application.css`. Run `bin/rails dartsass:build` to compile, or use `bin/dev` for watch mode.
- **JS**: Importmap pins in `config/importmap.rb` point to vendored files in `vendor/javascript/`. No build step — browser resolves imports via the importmap. When vendoring new JS libraries, use **self-contained ESM bundles** (e.g. from `esm.sh/<pkg>/es2022/<pkg>.bundle.mjs`). UMD modules lack `export default` and won't work with importmap. Modular ESM (with sub-module imports) won't resolve either — must be a single file.
- **Propshaft** serves all assets (from app, vendor, and gem directories) with fingerprinted URLs. It does no compilation.
- **Stylesheet load order** (in `application.html.haml`): Vendor CSS (Select2, Flatpickr) loads **before** `application.css` so that our SCSS overrides win the cascade at equal specificity.
- **Bootstrap JS is UMD** (not ESM). It's pinned in importmap but has no named or default exports — `import { Popover } from "bootstrap"` and `import Bootstrap from "bootstrap"` both fail at runtime. For interactive components that would normally need Bootstrap JS (popovers, tooltips, collapses), use **CSS-only implementations** (`:focus`/`:focus-within` patterns) instead. See `.help-popover-trigger` in `application.scss` for the pattern.
- **Chart.js is UMD** (same situation as Bootstrap). Pinned in importmap as `chart.js`. Use a side-effect import (`import "chart.js"`) to load the UMD bundle, then access `window.Chart`. Do NOT use `import Chart from "chart.js"` — it returns `undefined`. The `chart_controller.js` Stimulus controller handles rendering; it supports chart types `stacked-bar`, `histogram`, and `grade-distribution`. Pass data as JSON via `data-chart-data-value` attributes.
- **Turbo Drive is enabled globally**. Never use `DOMContentLoaded` in app code — it only fires once on the initial page load. Use `turbo:load` instead, which fires on both initial load and every Turbo navigation. Prefer Stimulus controllers over inline `<script>` blocks when possible.

## Version Control

- Uses **Mercurial (hg)**, not Git. The `.git` directory does not exist.
- **Commit messages must lead with WHY, not what.** The first paragraph explains the problem or motivation — why this change exists and what was wrong before. The bullet list or second paragraph covers what changed. The diff already shows the "what"; the message must provide the "why" that the diff cannot. This is top priority for every commit.

## Authentication

- Session-based login with `has_secure_password` (bcrypt)
- `ApplicationController` provides `current_user`, `logged_in?`, and `require_login` (applied to all controllers by default)
- Controllers that allow unauthenticated access must `skip_before_action :require_login`
- Login page uses a separate `auth` layout (no sidebar)

## Roles & Permissions

- **Permission catalog is code** (`Permission::CATALOG`, 6 keys); **roles are DB rows** (`Role`) bundling keys, with DAG inheritance via `role_inheritances`. Admin CRUD at `/roles`. Seeded roles: `admin` (locked), `staff`, `minimal`, `public_info`; new users default to `public_info`.
- **Check permissions via `user.can?("key")`**, writes via `require_admin`, reads via `require_permission("key")` in controllers (both live in `ApplicationController` — do NOT re-define per controller).
- **Advisor is data, not a role**: `advisees.read_full` activates only through `advisorships` rows (history-preserving join of student↔staff; `users.staff_id` links the account). Scoped checks go through `user.can_view_student_fully?(student)` / `user.can_view_grades?(student)` — never re-derive advisee logic.
- **students.read_minimal limits fields, not rows** (full roster browse, minimal columns). `students.read_full` does NOT include grade values — those are `grades.read` / advisee scope.
- **LINE tools declare `permission:`** at registration; definitions are filtered per user, the executor re-checks, and student-scoped tools check per student (see `docs/llm-data-query.md`).
- **Reports carry a permission key** in `Reports::Catalog` (`access:`); the hub filters by `current_user.can?`.
- Spec: `docs/superpowers/specs/2026-07-22-roles-permissions-design.md`.

## Development

```
bin/dev                  # starts Rails server + dartsass:watch via foreman
bin/rails server         # starts Rails server only (no SCSS recompilation)
AUTO_LOGIN=1 bin/dev     # bypass login, auto-authenticate as user ID 1
```

- `AUTO_LOGIN` env var: set to a user ID to skip authentication. Only use in development.
- Seed data: `bin/rails db:seed` creates a super admin at ID 1 (`root` / `password123`), a placeholder program, and loads staff/program seeds from `db/seeds/`.
- Seed files in `db/seeds/` are auto-loaded by `seeds.rb`. To re-seed a single file: `bin/rails runner "load Rails.root.join('db/seeds/foo.rb')"`.

## Styling Guidelines

- **Color palette from shadcn**: Theme colors are generated with [shadcn themes generator](https://shadcnthemes.app/generator), converted from oklch to hex, and mapped to Bootstrap Sass variables. See `docs/shadcn-color-mapping.md` for the full mapping and update procedure. Key: `$card-bg` and `$popover-bg` come directly from the palette; `$input-bg` and other surface colors are derived from `$dark` via `lighten()`.
- **Sass variable overrides first**: To customize Bootstrap, override Sass variables (e.g. `$card-bg`, `$body-bg`) **before** the `@import "scss/bootstrap"` line in `application.scss`. Bootstrap uses `!default`, so pre-defined variables take precedence. Avoid overriding Bootstrap's CSS variables (e.g. `--bs-card-bg`) in theme selectors — Bootstrap components often re-declare them on the element itself, which wins over ancestor overrides.
- **Dark mode uses `$body-color-dark`**, not `$body-color`. The app runs with `[data-bs-theme="dark"]`, so Bootstrap applies dark-mode Sass variables (e.g. `$body-color-dark`, `$body-bg-dark`) via CSS variables at runtime. Override `$body-color-dark` before the import to change the font color; `$body-color` only affects light mode.
- **Derive surface colors from `$dark`**: Use Sass functions (`lighten`, `darken`) on `$dark` for input/addon backgrounds so they stay in sync when the base changes. Card and popover backgrounds come directly from the shadcn palette (see mapping doc).
- **Post-import variables**: Variables that depend on Bootstrap internals (e.g. `$input-icon-color` uses `$light`) must be defined **after** `@import "scss/bootstrap"`, not before.
- **Table borders**: Do not use Bootstrap's `$table-border-color` — it has no effect on cell borders due to a Bootstrap bug (see `docs/bootstrap-table-border-bug.md`). Use our custom Sass variables (`$table-row-border-color`, `$table-head-border-color`, `$table-head-border-width`) defined in `application.scss`, applied via post-import CSS rules.
- **IMPORTANT — 3rd-party CSS overrides in `application.scss`**: Vendored libraries (Flatpickr, Select2, etc.) hardcode their own colors, font sizes, and SVG fills that do NOT read Bootstrap CSS variables or respect `[data-bs-theme="dark"]`. We override these in `application.scss`, which loads AFTER the vendor stylesheets so same-specificity rules win the cascade. **Every override block MUST be extensively commented**: start with a header explaining WHY the overrides exist (the library hardcodes X instead of using Bootstrap vars), then annotate each rule with what the original hardcoded value was (e.g. `// was #343a40`). This is critical because without comments, future readers cannot tell whether a rule is a cosmetic tweak or a required fix for a broken 3rd-party default.

## Testing

- **Framework**: Minitest + fixtures. System tests use Capybara + Selenium + headless Firefox (ESR).
- **After implementing a feature**: ask whether to write tests before proceeding.
- **Before writing tests**: briefly discuss what will be tested and get user input.
- **Model tests**: cover validations, associations, scopes, and custom methods.
- **System tests**: for any work involving UI — cover the happy path and key error states.
- **Run tests**: `bin/rails test` (unit/model), `bin/rails test:system` (system).
- **ActiveStorage `file.open` tempfile lifetime**: The tempfile created by `file.open` is deleted when the block exits. Do NOT `return` a Roo spreadsheet object from inside `file.open` — the underlying file will be gone when you try to read rows. Use a block pattern (e.g. `with_spreadsheet { |ss| ... }`) that keeps all processing inside the block.

## LINE Integration

Bot integration for LINE Messaging API. See `docs/line-integration.md` for architecture and dev setup.

- Webhook: `POST /line/webhook` (exposed via reverse proxy, rest stays intranet)
- Account linking: web UI at `/line_account` generates a token, user sends `link <token>` in LINE chat
- Adding commands: one file in `app/services/line/commands/` + one entry in `MessageRouter::COMMAND_MAP`
- Webhook controller inherits `ActionController::API` (not `ApplicationController`) to skip CSRF, auth, and browser checks
- **LLM data query tools**: See `docs/llm-data-query.md` for the meta-tool design (enum-based dispatch, query handlers)
- **Tool chain audit**: See `docs/tool-chain-audit.md` for how tool calls are persisted, logged, and inspected
- **Quick link (admin onboarding)**: See `docs/line-quick-link.md`. Unlinked LINE users are recorded as `LineContact` (bounded JSON messages, rate-limited). Admin reviews at `/line_contacts` and clicks "Create & Link" — zero friction for the VIP.

## UI Component Conventions

- **Badges**: Every badge must use a named semantic `.badge-*` class — never raw Bootstrap `bg-*` classes. When introducing a new badge, add a new `.badge-<concept>` class in `application.scss` following the frosted style (semi-transparent tinted background, subtle border) rather than reusing an existing class with a different meaning. Existing classes: `.badge-admin`, `.badge-role`, `.badge-staff`, `.badge-minimal`, `.badge-public-info`, `.badge-active`, `.badge-inactive`, `.badge-graduated`, `.badge-on-leave`, `.badge-retired`, `.badge-bachelor`, `.badge-master`, `.badge-doctoral`, `.badge-planned`, `.badge-confirmed`, `.badge-cancelled`, `.badge-pending`, `.badge-running`, `.badge-completed`, `.badge-failed`, `.badge-create-only`, `.badge-upsert`, `.badge-imported`, `.badge-manual`, `.badge-chulabooster`, `.badge-course-group`. Two classes may share similar colors if they represent different domain concepts. **Render badges data-driven** — derive the class from the value (e.g. `"badge-#{status.dasherize}"`) instead of if/elsif chains. This way adding a new value only requires a model constant + SCSS class, no view changes.
- **Icon action buttons**: Use ghost button classes (`.btn-ghost .btn-ghost-*`) for icon-only action links in tables. These extend Bootstrap's `btn-link` with no underline, custom color per variant, and a subtle tinted background on hover. Variants: `-primary` (view/show), `-secondary` (edit), `-danger` (delete). Do not use `btn-outline-*` for icon-only actions.
- **Icons**: Use Material Symbols (`%span.material-symbols`) for action icons, typically at `font-size: 18px` in tables. When placing icons inline with text, add `vertical-align: middle` — see `docs/material-symbols-vertical-align.md`.
- **Input group icons**: Styled with `$input-icon-color` (defined post-import in `application.scss`). Currently `darken($light, 5%)` — a dimmed version of the `$light` theme color.
- **Index page layout**: Title + action button live inside `.card-body.p-3` (no `.card-header`). The title row uses `.d-flex.justify-content-between.align-items-center.mb-3` with an `%h5.card-title`. See `docs/code-patterns.md` for the canonical template.
- **Card titles**: Use `.card-title` class on headings inside cards. Styled with `$light` color in `application.scss` to create visual hierarchy against muted body text.
- **Tables in cards**: Tables inside `.card` use transparent background (inherits card bg), no outer border (card provides rounding). Row separators are subtle, header border is more prominent. Column headers (`thead th`) are styled as quiet labels: uppercase, `0.7rem`, letter-spaced, muted color. Styled globally in `application.scss` — no extra classes needed on individual tables.
- **Table group headers**: Use `.table-group-header` on `%tr` rows with a `%td{colspan: N}` to visually separate groups (e.g. course groups, semesters) within a **single** table. This keeps columns aligned across groups — do NOT use separate tables per group. Styled as an accent band (tint, cyan inset bar, `$light` label). Additionally emit a `%tr.table-group-spacer{"aria-hidden" => "true"}` with an empty `%td{colspan: N}` before each group header **except the first** — it renders as a gap that separates the groups into blocks. See the Course History tables in `app/views/students/show.html.haml` for the canonical usage.
- **Dev style guide**: `/dev/styleguide` (development only) has an interactive Color Playground with live-preview color pickers for all base and derived variables, a sample form, badges, buttons, and tables. Use "Copy SCSS" to export changes.
- **Code patterns**: See `docs/code-patterns.md` for canonical controller, view, fixture, and test templates. Reference these when creating new resources instead of re-reading existing files. When creating or updating any resource, verify alignment against this checklist:
  - **Controller**: `before_action :require_admin, only: %i[new create edit update destroy]` + private `require_admin` method
  - **Index view**: `{"data-controller" => "datatable"}` on `.card`, `{"data-datatable-target" => "table"}` on `%table`, "New" button wrapped in `- if current_user.admin?`, edit/delete actions wrapped in `- if current_user.admin?`
  - **Edit view**: "Back" button links to the show page (`thing_path(@thing)`), not the index
  - **Model**: Enum-like fields get a frozen `FOOS` array constant + `FOO_ICONS` hash constant; validations reference the constant
  - **Form dropdowns**: Use `options_for_select` with `data-icon` attributes from the model's icon constant, not a plain array
- **Resource icons**: Centralized in `ApplicationHelper::RESOURCE_ICONS` — maps controller names to Material Symbols icon names. The `resource_icon` helper renders the icon span. Used in the sidebar nav and card titles. To add a new resource icon, add one entry to the hash.
- **Domain icon mappings**: Codify icon associations as frozen hash constants on the model (e.g. `Student::STATUS_ICONS`). These map domain values (not pages) to icons. In forms, pass icons as `data-icon` attributes on `<option>` elements via `options_for_select`. The `select2_controller.js` is generic — it detects `data-icon` automatically and renders Material Symbols icons at reduced size and opacity so the text label remains primary.
- **Visual hierarchy in forms**: Supporting elements (labels, icons) recede so input values stand out. Form labels use muted color + smaller font (like `thead th`). Select2 dropdown icons render at `16px` / `opacity: 0.5`. Input group icons use `$input-icon-color`. Do not give labels and values equal visual weight.
- **CSS-only popovers**: Use `.help-popover-trigger` with a child `.help-popover-content` span. Shows on `:focus`, no JS needed. Used for field help text in import mapping. Prefer this over Bootstrap JS popovers (see Asset Pipeline note about Bootstrap JS being UMD).
- **Inline editing (Turbo Frames)**: Used by Rooms for simple reference-data CRUD on the index page. Pattern: a `turbo_frame_tag "room_form"` placeholder on the index page; "New"/"Edit" links target this frame (`data-turbo-frame: "room_form"`) to load the form inline; the form itself targets `_top` (`data: { turbo_frame: "_top" }`) so the redirect after save does a full page navigation (refreshing the DataTable). This is necessary because DataTables manages its own DOM — Turbo Streams can't update it. Only use this pattern for simple reference tables; standard separate-page CRUD is preferred for complex resources.

## Data Model Conventions

- **ProgramGroup + Program (revisions)**: `ProgramGroup` represents a conceptual program (CP, CM, CS, SE, CD, CEDT). `Program` represents a specific curriculum revision with its own `program_code` and `year_started`. Groups: CP (Bachelor), CEDT (Bachelor), CM (Master of Eng), CS (Master of Sci), SE (Master of Sci), CD (Doctoral), OTHER (placeholder).
  - Shared attributes (`name_en`, `name_th`, `degree_level`, `degree_name`, `degree_name_th`, `field_of_study`) live on `ProgramGroup` only. `Program` delegates these — `program.name_en` works in Ruby via `delegate`, but SQL queries must join through `program_groups` (e.g. `Program.joins(:program_group).where(program_groups: { name_en: "..." })`).
  - Student and StaffProgram `belongs_to :program` (the specific revision). Course is many-to-many with programs via `program_courses` (see the "Course groups are per-pairing" bullet below) — it has no `program_id`. Cross-revision queries go through the group: `program_group.students` or `Student.joins(program: :program_group).where(program_groups: { code: "CP" })`.
  - `ProgramGroup` is read-only in the UI (managed via seeds). `Program` has full CRUD with a group dropdown.
  - Sidebar "Programs" links to `/program_groups`. The flat all-revisions list is at `/programs`.
- **Program `program_code`**: A unique 4-digit string (e.g. `"0018"`, `"4784"`) from the university's official system. This is the **business key** — use it for all external lookups (imports, seeds, APIs). Rails auto-increment `id` is only for internal associations/foreign keys. Seeds use `find_or_initialize_by(program_code:)`.
- **Course `course_no` as cross-revision key**: The same course (e.g. Algorithm Design) exists as multiple rows with different `revision_year` values. `course_no` is stable across revisions and serves as the implicit grouping key — no parent model needed. Cross-revision queries: `Grade.joins(:course).where(courses: { course_no: "2110327" })`.
- **Course groups are per-pairing**: `program_courses.course_group_code` (raw university code, e.g. `"4784-C"` = `<program_code>-<suffix>`) tags each program↔course pairing with its curriculum group. Labels + display order come from `ProgramCourse::COURSE_GROUP_LABELS` (frozen, full-code keys; unknown codes render as their raw suffix). Populated by `chulabooster:sync_program_courses` (fill-blank-only, conflicts report-only) + one-time `program_courses:backfill_legacy_groups`. `courses.course_group` is **deprecated** (still read by students/show Course History; drop both together later). Managed in the UI from the program page's Curriculum card.
- **Year fields are Buddhist Era (B.E.)**: `admission_year_be` (Student), `year_started_be` (Program), `revision_year_be` (Course) all store B.E. years (e.g. 2567 = 2024 CE). Importers auto-convert CE→BE by adding 543 when the value is < 2400. **Exception**: `Grade#year_ce` stores Gregorian/C.E., not B.E. — named `_ce` deliberately so this doesn't get misread as another B.E. field.
- **Cohort/generation notation**: the department refers to cohorts as `[program_group][generation]` (e.g. `CP53` = the 53rd CP intake = admission year B.E. 2569). Epochs (`first_intake_year_be`) live on `ProgramGroup`, seeds-managed institutional knowledge — resolve generation ↔ admission year via `ProgramGroup#year_for_generation` / `#generation_for_year`. Tools accept a `generation` param directly; never make the LLM do the arithmetic itself.
- **Student name display**: Use `Student#display_name` (prefers `full_name_th`, falls back to `full_name`) in all index pages, tables, and list contexts. Reserve `full_name` / `full_name_th` for show-page detail fields where both languages are displayed explicitly.
- **Staff name display**: Use `Staff#display_name_th` (prefers Thai, falls back to English) in all dropdowns, tables, and display contexts. Reserve `display_name` (English) for export/import matching where column data is in English.
- **Advisorships**: `advisorships(student_id, staff_id, started_on, ended_on, note)` — current = `ended_on IS NULL`; co-advisors legal; same pair active once. Managed from the student show page card; bulk via `Importers::AdvisorshipImporter`. Import modes: `create_only` = additive; `upsert` = **per-student snapshot** (the file's blank-End-Date rows are the complete current-advisor set for each listed student — stale current rows get `ended_on = today`, history rows are never deleted). An End Date column backfills already-ended advisorships.

## Teaching Schedule

Course offering, section, time slot, and teaching assignment tracking. See `docs/teaching-schedule.md` for full design.

- **Design docs**: `docs/teaching-schedule.md` (CRUD + import/export), `docs/schedule-reports.md` (reports), `docs/schedule-scraper.md` (web scraper)
- **Models**: Semester, Room, CourseOffering, Section, TimeSlot, Teaching — plus changes to Course (`description`, `description_th`, `has_many :course_offerings`), Staff (`initials`, `has_many :teachings`), Grade (`section_id` nullable FK)
- **Key conventions**:
  - `Semester` is the navigational parent (not inline year+semester like Grade)
  - `Teaching` belongs to **Section**, not TimeSlot — a staff member teaches the whole section
  - Section numbers can be non-sequential (1, 5, 99, 302)
  - `Staff#initials` maps to the 3-letter codes used by the university registration system (e.g., "NNN", "PKY")
- **CSV import**: `Importers::ScheduleImporter` — flat format, one row per time slot, find-or-create nested records
- **CSV export**: `Exporters::ScheduleExporter` — reverse of import, same format. Available via `GET /semesters/:id/export`
- **Nested forms**: `accepts_nested_attributes_for` chain (CourseOffering → Sections → TimeSlots + Teachings). `nested_fields_controller.js` handles dynamic add/remove with configurable `placeholder` value for multi-level nesting (`NEW_RECORD` for sections, `NEW_TIME_SLOT` / `NEW_TEACHING` for sub-levels). Select2 auto-connects on dynamically inserted elements via Stimulus MutationObserver. No `reject_if: :all_blank` — blank nested records show validation errors instead of being silently dropped.
- **Schedule reports**: `SchedulesController` with 7 read-only reports (room, staff, workload, curriculum, student, conflicts, teaching matrix). Shared `_week_calendar.html.haml` partial accepts `entries` array of hashes. See `docs/schedule-reports.md`.

## Schedule Scraper

Fetches schedule data from external university websites. See `docs/schedule-scraper.md` for full design.

- **Config**: `config/scraper.yml` — rate_limit, request_timeout, retry_count, retry_delay per environment
- **Backends**: `Scrapers::CuGetReg` (GraphQL, recommended) and `Scrapers::CasReg` (HTML scraping, fallback)
- **Console helpers**: `Scrapers::CuGetReg.scrape("2110327", 2568, 2)` (fetch only), `scrape!` (fetch + import)
- **Rake task**: `bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=2`
- **Web UI**: `/scrapes` — admin triggers scrape job, monitors progress, views history
- **Teacher initials are faculty-scoped**: the registrar's 3-letter codes are only unique within
  the course-owning faculty (CULI's "NNN" ≠ Engineering's "NNN"). Teachings are only auto-created
  for `21xxxxx` courses (+ `Scrapers::Base::CROSS_FACULTY_TEACHING_ALLOWLIST` exceptions); other
  local-staff hits are report-only via `Scrape#cross_faculty_matches`.

## Import System

Multi-step flow: upload (`create`) → column mapping (`mapping`) → execute (`execute`). `DataImport` stays in `pending` state until the user confirms mapping. Failed imports can be retried (reset to `pending`).

- **Importer interface**: Subclasses of `Importers::Base` implement `self.attribute_definitions` returning an array of hashes: `{ attribute:, label:, required:, aliases:, help:, fixed_options: }`. Base provides derived class methods: `required_attributes`, `attribute_labels`, `auto_map(headers)`.
  - `aliases`: list of column name variants (English + Thai) for auto-mapping
  - `help`: optional string, renders a CSS-only popover icon next to the field label
  - `fixed_options`: optional lambda returning `[[label, value], ...]` for relational fields — renders a `<select>` instead of text input when user picks "fixed value" mode
- **Adding a new importer**: Create `app/services/importers/foo_importer.rb` extending `Base`, implement `self.attribute_definitions` + private methods (`find_existing_record`, `build_new_record`, `transform_attributes`, `unique_key_fields`), add an entry to `DataImport::IMPORTERS`.
- **Column mapping storage**: `column_mapping` JSON maps attribute names to file column headers. `default_values` JSON maps attribute names to constant values. An attribute is in one or the other, never both.
- **Roo float coercion**: Roo reads numeric Excel cells as floats (e.g. `0018` → `18.0`). For string-like numeric fields (program codes, student IDs), strip `.0` with `.to_s.gsub(/\.0\z/, "")`. For program_code lookups, also zero-pad to 4 digits with `.to_i.to_s.rjust(4, "0")`.

## ChulaBooster Integration

Integration with ChulaBooster (CB), the university's registrar system: a read-only client +
reconciler, a snapshot cache, and authoritative sync write paths (students, courses, grades —
dry-run by default, `COMMIT=1` to write). Production syncs ran 2026-07-05/06; local and CB are
converged (re-run the snapshot + syncs after CB's next ETL refresh to pick up newly posted
grades). See `docs/superpowers/specs/2026-07-01-chulabooster-reconciliation-design.md`
(reconciliation design), `docs/chulabooster-program-crosswalk.md` (program-matching findings +
sync policy), and `docs/chulabooster-client-guide.md` (CB's API contract).

- **Read-only client + reconciler**: `app/services/chulabooster/client.rb` (GET-only, paginated),
  `reconciler.rb` + `mappers/*.rb` (per-entity comparison), `report_writer.rb` (console + CSV
  reports). Run via `bin/rails chulabooster:reconcile`.
- **Snapshot cache**: `bin/rails chulabooster:snapshot` dumps all 5 CB entities to disk once
  (`app/services/chulabooster/snapshotter.rb`); `SnapshotClient` lets `reconcile` (or any other
  analysis) run offline against the cache via `SNAPSHOT_DIR=`. Prefer this over repeated live
  reconciliation runs — the full pull (mainly `student_courses`, ~49k rows) takes tens of minutes.
- **CB's program identifiers are coarser than ours**. `Program.alternative_program_code` holds
  each program's CB `major_code` (seeded; CP/CM/CD share `21100` by CB's design). See
  `docs/chulabooster-program-crosswalk.md` for the verified mapping and the sync policy this
  implies: **local program/student data is authoritative; CB is additive-only** (bring in students
  CB has that we don't) and must never overwrite existing local program assignments.
- **Authority is per-field, not global — `Student#status` is the opposite of program identity.**
  Local `status` defaults to `"active"` at import and is never re-confirmed, so it drifts stale;
  CB's status code is the more reliable signal here (~99% validated against local `graduated`/
  `retired`, which — unlike `active` — require an active human decision to set). See
  `docs/chulabooster-student-status-crosswalk.md`. Same non-destructive rule applies: even where
  CB is more likely right, discrepancies are reported for human review, never auto-corrected.
- **Student sync (Phase 2a)**: `bin/rails chulabooster:sync_students` — dry-run by default,
  `COMMIT=1` to create CB-only students, `SNAPSHOT_DIR=` to run offline. Resolution logic:
  `Chulabooster::ProgramResolver` (major_code + student_id heuristic + majority-enrollment twin
  default, every assumption flagged in `remark`); status via `Chulabooster::StatusCodes`; raw CB
  code mirrored to `students.cb_status_code`. Report-only discrepancy CSVs for existing students.
  Documented on the admin **Data Sources** page at `/data_sources` (`/chulabooster` redirects
  there), alongside the CSV/Excel, CuGetReg, and reg.chula ingestion paths. Content lives in the
  `DataSource::SOURCES` constant — every source must state what it does *not* provide.
- **Course + grade sync (Phase 2b)**: `bin/rails chulabooster:sync_courses` then
  `chulabooster:sync_grades` — same dry-run-default / `COMMIT=1` / `SNAPSHOT_DIR=` contract.
  Additive creates plus two audited correction classes: auto-generated course-row backfill
  (placeholder stubs AND "copied" clones — both are machine guesses, promoted to `"none"` after
  backfill) and non-manual grade-value corrections (CB is registrar of record for grades;
  `manual` rows and CB-blank-vs-local-value are report-only). Grade identity is revision-insensitive
  (`student, course_no, year_ce, semester`) — full-key matching would duplicate
  revision-shadowed enrollments. New grades get `source: "chulabooster"`. Missing courses at
  grade time: exact → closest-revision copy → placeholder ladder. Design:
  `docs/superpowers/specs/2026-07-05-chulabooster-course-grade-sync-design.md`.
- **Program-course sync**: `bin/rails chulabooster:sync_program_courses` — links CB-only
  pairings and fills blank `course_group_code` tags (same dry-run/`COMMIT=1`/`SNAPSHOT_DIR=`
  contract; differing tags report-only). Run `program_courses:backfill_legacy_groups` after
  it, once, to fill what CB doesn't cover.

## Production

- **Website server: `dae@10.0.5.12`**, app at `~/cp-api`, Passenger on port 80 (`:3000` is closed). Not to be confused with `10.0.5.59` in `docs/line-integration.md` — that is the LLM-backend-side production server, a different machine.
- **Deploy** (server has no GitHub key — push directly over ssh): `hg push ssh://10.0.5.12/cp-api`, then on the server `hg update tip`, `bundle check || bundle install`, `RAILS_ENV=production bin/rails db:migrate dartsass:build assets:precompile` (rvm gemset `ruby-3.4.8@cp-api`, DB password env `CP_API_DATABASE_PASSWORD`), then `touch tmp/restart.txt`. Check `hg parent` on the server before pushing to catch server-side hotfixes.
- `config/llm.yml` is gitignored per-host — re-copy at deploy time only when it changed locally (production override: `log_level: headers`).
- `solid_queue` worker restart requires interactive sudo (`ssh -t 10.0.5.12 sudo systemctl restart solid_queue`) — needed only when job-side code changes.
