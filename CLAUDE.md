# CP-API

Backend for the Department of Computer Engineering, Chulalongkorn University.
Read-only API for student information (info, classes, scores) with a frontend for viewing data.
Data is imported via CSV/Excel and fetched from external data providers.

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

## Authentication

- Session-based login with `has_secure_password` (bcrypt)
- `ApplicationController` provides `current_user`, `logged_in?`, and `require_login` (applied to all controllers by default)
- Controllers that allow unauthenticated access must `skip_before_action :require_login`
- Login page uses a separate `auth` layout (no sidebar)

## Development

```
bin/dev                  # starts Rails server + dartsass:watch via foreman
bin/rails server         # starts Rails server only (no SCSS recompilation)
AUTO_LOGIN=1 bin/dev     # bypass login, auto-authenticate as user ID 1
```

- `AUTO_LOGIN` env var: set to a user ID to skip authentication. Only use in development.
- Seed data: `bin/rails db:seed` creates a super admin at ID 1 (`superadmin` / `password123`).
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

## UI Component Conventions

- **Badges**: Every badge must use a named semantic `.badge-*` class — never raw Bootstrap `bg-*` classes. When introducing a new badge, add a new `.badge-<concept>` class in `application.scss` following the frosted style (semi-transparent tinted background, subtle border) rather than reusing an existing class with a different meaning. Existing classes: `.badge-admin`, `.badge-editor`, `.badge-viewer`, `.badge-active`, `.badge-inactive`, `.badge-graduated`, `.badge-on-leave`, `.badge-retired`, `.badge-bachelor`, `.badge-master`, `.badge-doctoral`, `.badge-planned`, `.badge-confirmed`, `.badge-cancelled`, `.badge-pending`, `.badge-running`, `.badge-completed`, `.badge-failed`, `.badge-create-only`, `.badge-upsert`. Two classes may share similar colors if they represent different domain concepts. **Render badges data-driven** — derive the class from the value (e.g. `"badge-#{status.dasherize}"`) instead of if/elsif chains. This way adding a new value only requires a model constant + SCSS class, no view changes.
- **Icon action buttons**: Use ghost button classes (`.btn-ghost .btn-ghost-*`) for icon-only action links in tables. These extend Bootstrap's `btn-link` with no underline, custom color per variant, and a subtle tinted background on hover. Variants: `-primary` (view/show), `-secondary` (edit), `-danger` (delete). Do not use `btn-outline-*` for icon-only actions.
- **Icons**: Use Material Symbols (`%span.material-symbols`) for action icons, typically at `font-size: 18px` in tables.
- **Input group icons**: Styled with `$input-icon-color` (defined post-import in `application.scss`). Currently `darken($light, 5%)` — a dimmed version of the `$light` theme color.
- **Index page layout**: Title + action button live inside `.card-body.p-3` (no `.card-header`). The title row uses `.d-flex.justify-content-between.align-items-center.mb-3` with an `%h5.card-title`. See `docs/code-patterns.md` for the canonical template.
- **Card titles**: Use `.card-title` class on headings inside cards. Styled with `$light` color in `application.scss` to create visual hierarchy against muted body text.
- **Tables in cards**: Tables inside `.card` use transparent background (inherits card bg), no outer border (card provides rounding). Row separators are subtle, header border is more prominent. Column headers (`thead th`) are styled as quiet labels: uppercase, `0.7rem`, letter-spaced, muted color. Styled globally in `application.scss` — no extra classes needed on individual tables.
- **Table group headers**: Use `.table-group-header` on `%tr` rows with a `%td{colspan: N}` to visually separate groups (e.g. course groups, semesters) within a **single** table. This keeps columns aligned across groups — do NOT use separate tables per group. Styled with subtle background and stronger top border.
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

- **Program `program_code`**: A unique 4-digit string (e.g. `"0018"`, `"4784"`) from the university's official system. This is the **business key** — use it for all external lookups (imports, seeds, APIs). Rails auto-increment `id` is only for internal associations/foreign keys. Seeds use `find_or_create_by!(program_code:)`.
- **Year fields are Buddhist Era (B.E.)**: `admission_year_be` (Student), `year_started` (Program), `revision_year` (Course) all store B.E. years (e.g. 2567 = 2024 CE). Importers auto-convert CE→BE by adding 543 when the value is < 2400.
- **Student name display**: Use `Student#display_name` (prefers `full_name_th`, falls back to `full_name`) in all index pages, tables, and list contexts. Reserve `full_name` / `full_name_th` for show-page detail fields where both languages are displayed explicitly.
- **Staff name display**: Use `Staff#display_name_th` (prefers Thai, falls back to English) in all dropdowns, tables, and display contexts. Reserve `display_name` (English) for export/import matching where column data is in English.

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
- **Schedule reports**: `SchedulesController` with 6 read-only reports (room, staff, workload, curriculum, student, conflicts). Shared `_week_calendar.html.haml` partial accepts `entries` array of hashes. See `docs/schedule-reports.md`.

## Schedule Scraper

Fetches schedule data from external university websites. See `docs/schedule-scraper.md` for full design.

- **Config**: `config/scraper.yml` — rate_limit, request_timeout, retry_count, retry_delay per environment
- **Backends**: `Scrapers::CuGetReg` (GraphQL, recommended) and `Scrapers::CasReg` (HTML scraping, fallback)
- **Console helpers**: `Scrapers::CuGetReg.scrape("2110327", 2568, 2)` (fetch only), `scrape!` (fetch + import)
- **Rake task**: `bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=2`
- **Web UI**: `/scrapes` — admin triggers scrape job, monitors progress, views history

## Import System

Multi-step flow: upload (`create`) → column mapping (`mapping`) → execute (`execute`). `DataImport` stays in `pending` state until the user confirms mapping. Failed imports can be retried (reset to `pending`).

- **Importer interface**: Subclasses of `Importers::Base` implement `self.attribute_definitions` returning an array of hashes: `{ attribute:, label:, required:, aliases:, help:, fixed_options: }`. Base provides derived class methods: `required_attributes`, `attribute_labels`, `auto_map(headers)`.
  - `aliases`: list of column name variants (English + Thai) for auto-mapping
  - `help`: optional string, renders a CSS-only popover icon next to the field label
  - `fixed_options`: optional lambda returning `[[label, value], ...]` for relational fields — renders a `<select>` instead of text input when user picks "fixed value" mode
- **Adding a new importer**: Create `app/services/importers/foo_importer.rb` extending `Base`, implement `self.attribute_definitions` + private methods (`find_existing_record`, `build_new_record`, `transform_attributes`, `unique_key_fields`), add an entry to `DataImport::IMPORTERS`.
- **Column mapping storage**: `column_mapping` JSON maps attribute names to file column headers. `default_values` JSON maps attribute names to constant values. An attribute is in one or the other, never both.
- **Roo float coercion**: Roo reads numeric Excel cells as floats (e.g. `0018` → `18.0`). For string-like numeric fields (program codes, student IDs), strip `.0` with `.to_s.gsub(/\.0\z/, "")`. For program_code lookups, also zero-pad to 4 digits with `.to_i.to_s.rjust(4, "0")`.
