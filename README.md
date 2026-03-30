# CP-API

Backend for the Department of Computer Engineering, Chulalongkorn University.
Read-only API for student information (info, classes, scores) with a frontend for viewing data.
Data is imported via CSV/Excel and fetched from external data providers.

## Tech Stack

- Ruby 3.4.8, Rails 8.1
- MySQL 8.0 (user: `cp_api`)
- Propshaft (asset pipeline), Importmap (JS), Dart Sass (SCSS)
- HAML templates, Turbo, Stimulus
- Bootstrap 5.3 (vendored), DataTables, Chart.js, Select2, Flatpickr

## Requirements

- **Intranet-only**: All CSS, JS, and font assets are vendored locally. No CDN links or external URLs.

## Setup

```bash
bundle install
bin/rails db:create db:migrate db:seed
```

Seed creates a super admin (ID 1): `superadmin` / `password123`.

## Development

```bash
bin/dev                      # Rails server + dartsass:watch (via Foreman)
bin/rails server             # Rails server only (no SCSS recompilation)
AUTO_LOGIN=1 bin/dev         # Bypass login, auto-authenticate as user ID 1
```

## Testing

```bash
bin/rails test               # Unit/model tests
bin/rails test:system        # System tests (headless Firefox)
```

## Data Import

Multi-step flow via the web UI at `/data_imports`:

1. Upload CSV/Excel file
2. Map columns (auto-detected where possible)
3. Execute import

Supported importers: Students, Grades, Schedules, and more (see `DataImport::IMPORTERS`).

## Schedule Scraper

Fetches schedule data from external university registration systems.

### Web UI

Visit `/scrapes` (admin only) to trigger scrapes, monitor progress, and view history.

### CLI

```bash
# Rake task
bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=1

# Rails console (fetch only)
Scrapers::CuGetReg.scrape("2110327", 2568, 2)

# Rails console (fetch + import)
Scrapers::CuGetReg.scrape!("2110327", 2568, 2)
```

**Sources**: `cugetreg` (GraphQL, recommended), `cas_reg` (HTML scraping, fallback).

### Configuration

Rate limits, timeouts, and retry settings are in `config/scraper.yml` (per environment).

## Version Control

This project uses **Mercurial (hg)**, not Git.

## Documentation

Additional docs are in the `docs/` directory:

- `docs/teaching-schedule.md` — Teaching schedule CRUD and import/export
- `docs/schedule-reports.md` — Schedule report views
- `docs/schedule-scraper.md` — Scraper architecture and dev setup
- `docs/line-integration.md` — LINE bot integration
- `docs/code-patterns.md` — Canonical code patterns and templates
