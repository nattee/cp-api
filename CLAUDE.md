# CP-API

Backend for the Department of Computer Engineering, Chulalongkorn University.
Read-only API for student information (info, classes, scores) with a frontend for viewing data.
Data is imported via CSV/Excel and fetched from external data providers.

## Tech Stack

- Ruby 3.4.8, Rails 8.1
- MySQL 8.0 (user: `cp_api`, databases: `cp_api_development`, `cp_api_test`, `cp_api_production`)
- Propshaft (asset pipeline), Importmap (JS modules), Dart Sass (SCSS compilation)
- HAML templates, Turbo, Stimulus
- Bootstrap 5.3 (vendored SCSS + JS), DataTables, Chart.js

## Requirements

- **Intranet-only**: The app must work without public internet access. All CSS, JS, and font assets are vendored locally. No CDN links or external URLs in served pages.

## Asset Pipeline

- **CSS**: Dart Sass compiles `app/assets/stylesheets/application.scss` → `app/assets/builds/application.css`. Run `bin/rails dartsass:build` to compile, or use `bin/dev` for watch mode.
- **JS**: Importmap pins in `config/importmap.rb` point to vendored files in `vendor/javascript/`. No build step — browser resolves imports via the importmap.
- **Propshaft** serves all assets (from app, vendor, and gem directories) with fingerprinted URLs. It does no compilation.

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
