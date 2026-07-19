# Report hub consolidation (one honest door for reports)

**Date:** 2026-07-19
**Status:** Approved

> **Part 1 of 3.** A UX pressure-test of the report layer found three separable
> problems. This spec covers only the first — consolidating the report
> *navigation and catalog*. The other two are their own spec → plan → implement
> cycles and are **out of scope here**:
>
> 1. **Report hub consolidation** ← this spec
> 2. Home / launchpad to replace the Users-list root
> 3. Sticky term/program context across report forms

## Motivation

Reports are split across two hubs and one orphan, gated and grouped by *which
controller owns the code* rather than by *the question a user is asking*:

- **`/schedules`** (`SchedulesController`) — 7 timetable/workload/conflict
  reports. Filed under the "Teaching" nav section. Visible to all logged-in
  users.
- **`/reports`** (`ReportsController` + `Reports::Registry`) — 7 grade/academic
  reports. Filed under the admin-only "Admin" nav section. **Whole controller
  is `require_admin`.**
- **`/grades/distribution`** — reachable only via a "Distribution" button on the
  Grades index. In neither hub.

Three concrete failures follow:

1. **The word "Reports" over-promises and is gated on the wrong axis.** The
   sidebar "Reports" item holds only 7 of ~15 reports and is admin-only. A user
   wanting the room schedule or teaching matrix clicks "Reports", doesn't find
   them, and concludes the app can't do it — they live under "Schedules". The
   blanket admin gate exists for exactly *one* report in that hub (Data
   Coverage, which is genuinely admin-only) and drags six lecturer-facing
   reports behind it.
2. **The same task spans two menus.** "Look at teaching load" → Staff Workload
   is in `/schedules`; "Courses taught by a staff member in a year" is in
   `/reports`. Same intent, two menus, chosen by controller boundary.
3. **An orphan.** `/grades/distribution` has no hub; discover-by-accident only.

The `/reports` vs `/schedules` seam is invisible and unhelpful to users. The
line users actually feel is **domain (lecturer-facing analytics) vs. system
(admin-only operational health)** — and neither current hub is drawn on it.

The app is pre-public: one login, a few key testers, non-admin logins arriving
later with certainty. This is the cheapest moment to restructure — the cost of
consolidating rises with every real user added later. The design targets the
world where every user is a **lecturer** (see Access model).

### What is explicitly NOT broken (and stays untouched)

- **Report-ish cards embedded on entity show pages** (Student transcript +
  timetable, Program charts + roster, Course offerings + grade distribution,
  Staff teaching history + load, Semester roster). Answering "about X" where the
  user already is remains correct. The backlog's entity→report cross-link
  discipline (docs/backlog.md item 1) continues unchanged.
- **Each report's own page and query logic.** This is a navigation/catalog
  consolidation, not a rewrite of any report.

## Scope & non-goals

**In scope:** a single report hub page, a single catalog that drives that page
and the sidebar, per-report (not per-hub) access gating, relocating Data
Coverage out of the hub, adopting the grade-distribution orphan, and the
sidebar nav change.

**Out of scope:** the home/launchpad (spec 2), sticky term/program context
(spec 3), any change to a report's internal query or presentation, and any
change to entity show pages.

## Design

### 1. Unified hub taxonomy

One hub at `/reports`, a card grid grouped into four **lecturer-facing**
sections. Every card links to the report's existing page.

| Section | Reports | Underlying page (unchanged) |
|---|---|---|
| **Schedules** *(timetables & planning)* | Room Schedule, Staff Schedule, Student Timetable, Curriculum Calendar, Conflicts | `schedules/*` |
| **Teaching** *(teaching analytics)* | Staff Workload, Teaching Matrix, Staff Courses by Year | `schedules/workload`, `schedules/teaching_matrix`, `reports/staff_courses_by_year` |
| **Grades & Courses** | Grade Distribution by Course, Class Grade Distribution *(ex-orphan)*, Failing Students | `reports/semester_grade_distribution`, `grades/distribution`, `reports/failing_students` |
| **Students & Cohorts** | Cohort GPA, Credit Shortfall, Thesis Credits | `reports/cohort_gpa`, `reports/group_credit_shortfall`, `reports/thesis_credits` |

Two deliberate moves:

- **Schedules ≠ all teaching reports.** The Schedules section is the *timetable*
  task (calendar-format reports) plus Conflicts (a "is my timetable broken?"
  integrity check). Workload and Teaching Matrix are *matrices*, not calendars,
  so they move to a sibling **Teaching** section — even though today they render
  under `schedules/*`. A section maps to a consistent task **and** format; a
  timetable and a GPA table are different enough acts that lumping them would
  make a section a junk drawer. **This split is provisional** — see Open items.
- **Data Coverage leaves the hub** (see §5). With it gone, the hub is uniformly
  lecturer-facing: no admin-only section, no gating logic inside the hub.

### 2. Access model

Every user of this system is a **lecturer** (confirmed with the product owner,
2026-07-19). The `viewer`/`editor`/`admin` roles distinguish *edit rights*, not
*trust to see academic data*. Therefore:

- **All hub reports are visible to any logged-in user.** No privacy line on
  student-level reports (Failing Students, Cohort GPA, Credit Shortfall, Thesis
  Credits) — lecturers legitimately see student academic standing.
- **Gating moves from per-controller to per-report.** The registry reports were
  admin-only *only* because `ReportsController` blanket-applies `require_admin`.
  That blanket gate is removed; access is read from each catalog entry instead.
  After Data Coverage relocates, every hub entry is `access: :all`; the only
  `access: :admin` entry is Data Coverage, rendered outside the hub.

### 3. Report catalog (single source of truth)

Extend the existing `Reports::Registry` concept into one catalog that knows
**every** report — including the `schedules/*` reports and the class-distribution
report that render outside the registry framework. The hub index and the
sidebar render from this catalog; nothing hard-codes a report list in a view.

Each catalog entry carries:

| field | meaning |
|---|---|
| `key` | stable identifier |
| `title` | display label (see §6 for the two "grade distribution" names) |
| `description` | one-line card subtitle |
| `section` | `:schedules` / `:teaching` / `:grades` / `:students` (hub ordering) — or `:system` for out-of-hub |
| `path` | where the card links (a path helper result) |
| `access` | `:all` or `:admin` |
| `framework` | `:registry` (rendered by `ReportsController#show`) or `:external` (renders in its own controller/view) |

- **`:registry` entries** keep rendering through the generic
  `ReportsController#show` param-form → table/chart pipeline (unchanged). Their
  `path` is `report_path(key)`.
- **`:external` entries** (the `schedules/*` reports and `grades/distribution`)
  render in their existing controllers/views. Their `path` is that report's own
  route helper. The catalog holds only the metadata needed to list them on the
  hub and the nav; it does **not** try to render them.

`ReportsController#index` renders the hub from `catalog.reject { system }`,
grouped by `section`. `ReportsController#show` looks up the entry, enforces
`access` (per-report gate replacing the blanket `require_admin`), and 404s /
redirects unknown or `:external` keys (those are reached by their own routes).

Calendar reports deliberately stay out of the registry's table DSL — folding
them in buys nothing for findability and risks the working calendar code.

### 4. Navigation

- **One top-level "Reports" sidebar item**, visible to all logged-in users,
  linking to the hub. It **replaces both** current entries: the admin-only
  "Reports" under the Admin section, and "Schedules" under the Teaching section.
- **"Schedules" is no longer a nav item.** It is a section inside the hub, one
  click away. The `schedules/index` landing page can stay routable (some
  contextual deep-links and its "Back" buttons point at it) but is no longer the
  primary door; the hub is. *(Implementation choice to settle in the plan:
  either keep `schedules/index` as-is, or redirect it to the hub anchored at the
  Schedules section. Prefer the redirect so there is one landing page.)*
- **Contextual deep-links from entity pages are unaffected** — Semester/Staff
  pages linking to Teaching Matrix / Conflicts pre-filled still work; those
  point at the reports' own routes, which do not move.

### 5. Data Coverage relocation

Data Coverage (`reports/data_coverage`) is an operational data-pipeline health
check — "did term 2568/2 actually import?" — not lecturer analytics. It moves
**out of the hub** to the admin operational cluster:

- Remove its hub card (drop it from the hub-visible catalog; keep the entry with
  `section: :system, access: :admin`).
- It is already cross-linked from the Data Sources hub (docs/backlog.md item 1,
  2026-07-16). Surface it there prominently (a card/link on
  `data_sources/index`), since that is where the admin goes to ask "is my data
  healthy?". No new admin sidebar item required.
- Its route and admin gate are unchanged (`report_path("data_coverage")`, still
  admin via the per-report `access: :admin`).

### 6. Naming: the two grade-distribution reports

Consolidation puts two similarly-named reports in the same section, forcing
disambiguation (a feature, not a problem):

- **Grade Distribution by Course** — `reports/semester_grade_distribution`: one
  program group, one term, one row per course (grade counts + course GPA/SD).
- **Class Grade Distribution** — `grades/distribution`: subjects (by course-no
  prefix) × term across a year range, grade spread + N + GPA + pass-rate, with a
  class-GPA-by-term line chart.

Titles are set in the catalog; no view or query changes.

## Decisions & rationale

- **Consolidate navigation, not controllers.** The user-facing IA is what
  drives findability; physically merging `SchedulesController` into the registry
  framework is risk without user benefit. The catalog gives one door while each
  report keeps its home. *(Alternative rejected: rewrite every report as a
  registry report — large, and calendars don't fit the table DSL.)*
- **Per-report gating.** Fixes the inverted axis directly: the admin gate
  applies to the one report that needs it, not the hub it happened to live in.
- **Data Coverage out of the hub, not into an admin sub-section of it.** Keeps
  the hub uniformly lecturer-facing and eliminates gating branches inside it; the
  report joins the operational tools the admin already uses.
- **Schedules kept as a section (provisional).** Chosen for a recognizable
  task+format cluster; flagged for revisit because it is a pure labeling call
  with no downstream dependency.

## Open items (revisit, don't block)

- **Schedules/Teaching section split** — validate against real lecturer feedback
  once non-admin logins exist. Changing it is a catalog `section:` edit, nothing
  more.
- **`schedules/index` fate** — keep vs. redirect-to-hub; decide in the plan.
  Recommendation: redirect, so there is a single report landing page.

## Testing

- **Catalog (unit):** every report appears exactly once; sections and `access`
  are as specified; no `:all` entry is admin-gated and Data Coverage is
  `:admin`/`:system`.
- **`ReportsController` (integration):** a non-admin logged-in user can now load
  `reports#index` and each `:registry` hub report (previously 403/redirected);
  a non-admin is still blocked from `data_coverage`; unknown/`:external` keys on
  `#show` behave as specified.
- **System:** from the sidebar "Reports" link, the hub shows all four sections
  with the expected cards; a card in each section navigates to the right report;
  "Schedules" no longer appears as a separate sidebar item; Data Coverage is
  reachable from the Data Sources page and not from the hub.

## Backlog implications (docs/backlog.md)

- **Item 1 (entity→report cross-links):** report routes do not move, so existing
  pre-filled links keep working. Add the new hub as the canonical "browse all
  reports" destination.
- **Item 2 (report ↔ entity overlap review):** unchanged in substance; the
  overlap rule ("about X" on entity pages vs "across a set" in reports) is now
  *legible* to users because every "across a set" report lives behind one honest
  door. Update the status note to record the two-hubs→one-hub consolidation.
