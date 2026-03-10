# CP-API

Backend for the Department of Computer Engineering, Chulalongkorn University.
Read-only API for student information (info, classes, scores) with a frontend for viewing data.
Data is imported via CSV/Excel and fetched from external data providers.

## Tech Stack

- Ruby 3.4.8, Rails 8.1
- MySQL 8.0 (user: `cp_api`, databases: `cp_api_development`, `cp_api_test`, `cp_api_production`)
- Propshaft (asset pipeline), Importmap (JS modules), Dart Sass (SCSS compilation)
- HAML templates, Turbo, Stimulus
- Bootstrap 5.3 (vendored SCSS + JS), DataTables, Chart.js, Tom Select, Flatpickr

## Requirements

- **Intranet-only**: The app must work without public internet access. All CSS, JS, and font assets are vendored locally. No CDN links or external URLs in served pages.

## Asset Pipeline

- **CSS**: Dart Sass compiles `app/assets/stylesheets/application.scss` → `app/assets/builds/application.css`. Run `bin/rails dartsass:build` to compile, or use `bin/dev` for watch mode.
- **JS**: Importmap pins in `config/importmap.rb` point to vendored files in `vendor/javascript/`. No build step — browser resolves imports via the importmap. When vendoring new JS libraries, use **self-contained ESM bundles** (e.g. from `esm.sh/<pkg>/es2022/<pkg>.bundle.mjs`). UMD modules lack `export default` and won't work with importmap. Modular ESM (with sub-module imports) won't resolve either — must be a single file.
- **Propshaft** serves all assets (from app, vendor, and gem directories) with fingerprinted URLs. It does no compilation.
- **Stylesheet load order** (in `application.html.haml`): Vendor CSS (Tom Select, Flatpickr) loads **before** `application.css` so that our SCSS overrides win the cascade at equal specificity.

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

## Styling Guidelines

- **Sass variable overrides first**: To customize Bootstrap, override Sass variables (e.g. `$card-bg`, `$body-bg`) **before** the `@import "scss/bootstrap"` line in `application.scss`. Bootstrap uses `!default`, so pre-defined variables take precedence. Avoid overriding Bootstrap's CSS variables (e.g. `--bs-card-bg`) in theme selectors — Bootstrap components often re-declare them on the element itself, which wins over ancestor overrides.
- **Dark mode uses `$body-color-dark`**, not `$body-color`. The app runs with `[data-bs-theme="dark"]`, so Bootstrap applies dark-mode Sass variables (e.g. `$body-color-dark`, `$body-bg-dark`) via CSS variables at runtime. Override `$body-color-dark` before the import to change the font color; `$body-color` only affects light mode.
- **Derive surface colors from `$dark`**: Use Sass functions (`lighten`, `darken`) on `$dark` for all surface colors so they stay in sync when the base changes.
- **Post-import variables**: Variables that depend on Bootstrap internals (e.g. `$input-icon-color` uses `$light`) must be defined **after** `@import "scss/bootstrap"`, not before.
- **Table borders**: Do not use Bootstrap's `$table-border-color` — it has no effect on cell borders due to a Bootstrap bug (see `memory/bootstrap-table-border-bug.md`). Use our custom Sass variables (`$table-row-border-color`, `$table-head-border-color`, `$table-head-border-width`) defined in `application.scss`, applied via post-import CSS rules.
- **IMPORTANT — 3rd-party CSS overrides in `application.scss`**: Vendored libraries (Flatpickr, Tom Select, etc.) hardcode their own colors, font sizes, and SVG fills that do NOT read Bootstrap CSS variables or respect `[data-bs-theme="dark"]`. We override these in `application.scss`, which loads AFTER the vendor stylesheets so same-specificity rules win the cascade. **Every override block MUST be extensively commented**: start with a header explaining WHY the overrides exist (the library hardcodes X instead of using Bootstrap vars), then annotate each rule with what the original hardcoded value was (e.g. `// was #343a40`). This is critical because without comments, future readers cannot tell whether a rule is a cosmetic tweak or a required fix for a broken 3rd-party default.

## Testing

- **Framework**: Minitest + fixtures. System tests use Capybara + Selenium + headless Firefox (ESR).
- **After implementing a feature**: ask whether to write tests before proceeding.
- **Before writing tests**: briefly discuss what will be tested and get user input.
- **Model tests**: cover validations, associations, scopes, and custom methods.
- **System tests**: for any work involving UI — cover the happy path and key error states.
- **Run tests**: `bin/rails test` (unit/model), `bin/rails test:system` (system).

## LINE Integration

Bot integration for LINE Messaging API. See `docs/line-integration.md` for architecture and dev setup.

- Webhook: `POST /line/webhook` (exposed via reverse proxy, rest stays intranet)
- Account linking: web UI at `/line_account` generates a token, user sends `link <token>` in LINE chat
- Adding commands: one file in `app/services/line/commands/` + one entry in `MessageRouter::COMMAND_MAP`
- Webhook controller inherits `ActionController::API` (not `ApplicationController`) to skip CSRF, auth, and browser checks

## UI Component Conventions

- **Badges**: Every badge must use a named semantic `.badge-*` class — never raw Bootstrap `bg-*` classes. When introducing a new badge, add a new `.badge-<concept>` class in `application.scss` following the frosted style (semi-transparent tinted background, subtle border) rather than reusing an existing class with a different meaning. Existing classes: `.badge-admin`, `.badge-staff`, `.badge-viewer`, `.badge-active`, `.badge-inactive`, `.badge-graduated`, `.badge-on-leave`. Two classes may share similar colors if they represent different domain concepts.
- **Icon action buttons**: Use ghost button classes (`.btn-ghost .btn-ghost-*`) for icon-only action links in tables. These extend Bootstrap's `btn-link` with no underline, custom color per variant, and a subtle tinted background on hover. Variants: `-primary` (view/show), `-secondary` (edit), `-danger` (delete). Do not use `btn-outline-*` for icon-only actions.
- **Icons**: Use Material Symbols (`%span.material-symbols`) for action icons, typically at `font-size: 18px` in tables.
- **Input group icons**: Styled with `$input-icon-color` (defined post-import in `application.scss`). Currently `darken($light, 5%)` — a dimmed version of the `$light` theme color.
- **Index page layout**: Title + action button live inside `.card-body.p-3` (no `.card-header`). The title row uses `.d-flex.justify-content-between.align-items-center.mb-3` with an `%h5.card-title`. See `docs/code-patterns.md` for the canonical template.
- **Card titles**: Use `.card-title` class on headings inside cards. Styled with `$light` color in `application.scss` to create visual hierarchy against muted body text.
- **Tables in cards**: Tables inside `.card` use transparent background (inherits card bg), no outer border (card provides rounding). Row separators are subtle, header border is more prominent. Column headers (`thead th`) are styled as quiet labels: uppercase, `0.7rem`, letter-spaced, muted color. Styled globally in `application.scss` — no extra classes needed on individual tables.
- **Dev style guide**: `/dev/styleguide` (development only) has an interactive Color Playground with live-preview color pickers for all base and derived variables, a sample form, badges, buttons, and tables. Use "Copy SCSS" to export changes.
- **Code patterns**: See `docs/code-patterns.md` for canonical controller, view, fixture, and test templates. Reference these when creating new resources instead of re-reading existing files.
- **Resource icons**: Centralized in `ApplicationHelper::RESOURCE_ICONS` — maps controller names to Material Symbols icon names. The `resource_icon` helper renders the icon span. Used in the sidebar nav and card titles. To add a new resource icon, add one entry to the hash.
- **Domain icon mappings**: Codify icon associations as frozen hash constants on the model (e.g. `Student::STATUS_ICONS`). These map domain values (not pages) to icons. In forms, pass icons as `data-icon` attributes on `<option>` elements via `options_for_select`. The `tomselect_controller.js` is generic — it detects `data-icon` automatically and renders Material Symbols icons.
