# Home / Launchpad — Design

Date: 2026-07-20
Status: Approved
Part 2 of 3 in the report-findability decomposition
(Part 1: `2026-07-19-report-hub-consolidation-design.md`; Part 3: sticky term/program context, not yet specified)

## Problem

`config/routes.rb` sets `root "users#index"`. The first page any user sees after
signing in is a DataTable of every user account — username, email, name, role,
active flag, LLM enabled, model.

Three things are wrong with that:

1. **It answers a question nobody asked.** A lecturer signing in wants to reach a
   student, a course, or a report. The account roster is the one page in the app
   with no bearing on any of those.
2. **It miscategorises Users.** "Users" sits in the main sidebar nav beside
   Programs, Courses, Staff, Students and Grades, as if account administration
   were a domain entity. `UsersController` gates only
   `new/create/edit/update/destroy` behind `require_admin`; `index` and `show`
   are open to every logged-in user. Today the system has one login, so this is
   invisible. It stops being invisible the moment lecturers get accounts.
3. **It wastes the app's most valuable URL.** Part 1 established a single reports
   hub with four sections, but the sidebar can only afford one word ("Reports")
   for fourteen reports. The depth problem that hid six reports before Part 1 is
   still there — it has just moved down one level. The root page is the natural
   place to defeat it, and it is currently spent on a table of accounts.

## Goals

- Replace the root with a launchpad that maps the app and links one level deeper
  than the sidebar can.
- Stop Users from presenting as a domain entity, and gate it for the
  multi-lecturer world that is coming.
- Keep the reports listing derived from `Reports::Catalog`, so home and the hub
  cannot drift.

## Non-goals

- **No dashboard.** No counts, no freshness indicators, no "last import" tiles.
  Data-state questions are administrative and already have a home on
  `/data_sources`, which is where Part 1 moved Data Coverage. Home performs no
  queries, so it cannot go stale or slow.
- **No search box.** Considered and dropped; a jump-to-record field is a
  separate idea that should stand on its own merits, not ride in on a layout change.
- **No second taxonomy.** Home reuses Part 1's four report sections verbatim
  rather than inventing task-oriented groupings ("Plan a term", "Understand a
  student"). One taxonomy was the point of Part 1.
- **No sidebar rewrite**, and **no consolidation of the eight per-controller
  `require_admin` copies**. Both are discussed below and deliberately rejected.

## Design

### Route and controller

```ruby
root "home#index"
```

`HomeController#index` requires login (inherited `require_login`) and nothing
more. It performs no queries and assigns no records. It exposes two catalogs to
the view.

### Content source 1 — reports

Reports come from the existing `Reports::Catalog`: `hub_entries` filtered and
`grouped` exactly as `ReportsController#index` does it. Home renders the same
four sections, in the same order, with the same titles. Adding a report to the
catalog makes it appear on both surfaces; there is no second list to maintain.

`:system` entries (Data Coverage) are excluded from the Reports band by
`hub_entries`, as they already are from the hub.

### Content source 2 — `Navigation::AREAS`

Entity and tool areas have no catalog today; the sidebar hardcodes them as
repeated HAML. Part 2 adds a frozen array:

```ruby
module Navigation
  AREAS = [
    { key: "students", label: "Students", group: :records, access: :all,
      path_helper: :students_path,
      description: "Student records, transcripts and course history." },
    # ...
  ].freeze
end
```

Fields: `key` (for `resource_icon`), `label`, `description` (one sentence),
`path_helper` (symbol, resolved with `public_send`), `group`
(`:records | :teaching_setup | :admin | :account`), `access` (`:all | :admin`).

Covers: Programs, Courses, Staff, Students, Grades, Semesters, Rooms, Scraper,
LINE Account, and the admin tools (Users, Imports, Data Sources, API Events,
Chat Playground, Chat History, LINE Contacts, Style Guide).

### Rejected: driving the sidebar from `Navigation::AREAS`

A single list feeding both surfaces is the obvious move, and it does not survive
contact with the sidebar's actual behaviour:

- LINE Contacts and API Events render live badge counts in the view
  (`LineContact.count`, `ApiEvent.errors_since(24.hours.ago)`).
- Active-state matching spans multiple controllers
  (`%w[program_groups programs]`, `%w[reports schedules]`).

Encoding those means lambdas for badges and controller-arrays for highlighting —
more machinery than the duplication costs, and a lossy abstraction over two
surfaces that genuinely want different things. Home wants a sentence per area;
the sidebar wants a badge and an active state.

The duplication is instead guarded by a **parity test** (see Testing). That
catches the real failure mode — adding a nav item and forgetting home — without
the abstraction.

### Page structure

Four bands, top to bottom:

| Band | Contents | Treatment |
|---|---|---|
| **Records** | Programs, Courses, Staff, Students, Grades | Cards: icon, label, one-sentence description |
| **Teaching setup** | Semesters, Rooms, Scraper | Cards, same shape |
| **Reports** | The four `Reports::Catalog` sections, nested under one "Reports" heading | Sub-heading per section + plain link list |
| **Administration** | Users, Imports, Data Sources, API Events, Chat Playground, Chat History, LINE Contacts, Style Guide | Cards; rendered only when `current_user.admin?` |
| **Your account** | Profile, LINE Account | Cards; `access: :all` |

The fifth band exists because LINE Account fits none of the other four — it is a
personal setting, not a domain area and not an admin tool. Pairing it with
Profile (today reachable only from the sidebar's account dropdown) gives both a
visible home and keeps the account-level concerns together. `group: :account`.

**Reports render as link lists, not cards.** Mocked both ways. With fourteen
cards the Reports band takes roughly 70% of the page, pushes Records and Teaching
setup off-screen, and becomes a near-copy of the hub — which weakens the reason
to have both pages. As link lists, all four sections are visible at once, the
entity bands keep the top, and the division of labour is clean: **home says what
exists, the hub says what each one does.**

**Naming collision, resolved by nesting.** `Reports::Catalog::SECTIONS` contains
a section named "Teaching" (Staff Workload, Teaching Matrix, Staff courses by
year), and the sidebar has a "Teaching" group (Semesters, Rooms, Scraper). On the
sidebar these never meet; on home they would be two same-named headings inches
apart. Resolution: nest the report sections under a single "Reports" heading so
the collision reads as *Reports → Teaching*, and name the entity band **"Teaching
setup"**. `Reports::Catalog` is not renamed — Part 1's taxonomy was reviewed and
shipped, and re-cutting it to solve a layout adjacency is the wrong trade.

### Access

`Navigation::AREAS` entries carry `access`; the view filters on it and renders
the Administration band only for admins. This mirrors how `Reports::Catalog`
already handles its `:system` section, so home, hub and sidebar all express
access one way.

### Users changes

1. `index` joins the `require_admin` list.
2. `show` becomes **admin-or-self**. The account dropdown links
   `Profile → user_path(current_user)`, so a lecturer must keep access to their
   own record; they gain no ability to enumerate colleagues' accounts, roles or
   LLM settings.
3. The sidebar's Users item moves out of the main nav group into the existing
   `if current_user.admin?` Admin block, beside LINE Contacts and API Events.
4. **`UsersController#require_admin` must be retargeted to `root_path`.** It
   currently redirects to `users_path`. That is harmless while `index` is
   ungated; the moment step 1 lands, a non-admin hitting `/users` is redirected
   to `/users`, which redirects to `/users` — a redirect loop
   (`ERR_TOO_MANY_REDIRECTS`). This change is required, not cosmetic. LINE
   Contacts and Chat Messages already use `root_path`.

Note the symmetry: `root_path` only becomes a sane denial target *because* home
exists. Before Part 2, bouncing a user off a Users action sent them to the Users
list — the page they were just denied.

The eight per-controller `require_admin` copies are **not** consolidated;
`docs/code-patterns.md` establishes the per-controller private method as the
convention, and Part 1's lesson was to fix categorisation without starting a
refactor tour.

## Testing

### New

- **`test/controllers/home_controller_test.rb`** — root renders for a non-admin;
  the Administration band appears for an admin and not for a viewer; a report
  drawn from `Reports::Catalog` (e.g. Teaching Matrix) is linked, proving home
  reads the catalog rather than a hardcoded list.
- **`test/system/home_test.rb`** — sign in, land on home, click through to a
  report and arrive at the right page; Users is absent from the main nav for a
  non-admin.
- **Parity test** — render root **as an admin** (a viewer's sidebar omits the
  Admin block, so only an admin session exercises the full nav), collect every
  `href` under `#sidebar` and every `href` inside `<main>`, and assert the
  sidebar's set is a subset of `<main>`'s. Requires a small explicit allowlist
  for the deliberately sidebar-only links: the brand link and Sign Out. Profile
  needs no allowlist entry — it is on home, in the "Your account" band. This is
  what makes the "no sidebar refactor" decision safe.

### Existing tests that must change

These assert today's contract and will fail. Each is a legitimate update, but
they are named individually here so they get *rewritten to the new contract*
rather than weakened or deleted.

In `test/controllers/users_controller_test.rb` (setup logs in as `users(:viewer)`):

| Test | Change |
|---|---|
| `"non-admin can view index"` | Invert: expect redirect to `root_path` |
| `"non-admin can view show"` | Currently fetches `user_path(users(:admin))` — *another* user. Replace with two tests: self → success, other → redirect to `root_path` |
| `"non-admin cannot access new"` | `assert_redirected_to users_path` → `root_path` |
| `"non-admin cannot create"` | same |
| `"non-admin cannot access edit"` | same |
| `"non-admin cannot update"` | same |
| `"non-admin cannot delete"` | same |
| `"non-admin cannot generate line code"` | same |
| `"non-admin cannot unlink line"` | same |

The `"Only admins can perform this action."` flash message is unchanged.

**Unaffected:** `test/system/login_test.rb` asserts `assert_current_path
root_path` after sign-in and that an unauthenticated visit to `root_path`
redirects to login. Both stay true; only the page's content changes.

## Error handling

Home performs no queries, so it has no failure modes beyond the layout's own.
The single runtime risk is a `Navigation::AREAS` entry naming a `path_helper`
that does not resolve; both the home controller test and the parity test catch
that on first run.

## Open questions

None.
