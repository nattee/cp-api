# Home / Launchpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `users#index` root with a queryless launchpad that maps the app, lists every report from `Reports::Catalog`, and moves Users into admin territory.

**Architecture:** A new `HomeController#index` renders `app/views/home/index.html.haml` from two data sources: the existing `Reports::Catalog` (reports) and a new `Navigation::AREAS` frozen array (entity and tool areas). The controller runs no queries. The sidebar is deliberately *not* refactored to share `Navigation::AREAS`; a parity test guards the duplication instead.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, HAML, Bootstrap 5.3, Minitest + fixtures, Capybara + Selenium (headless Firefox), Mercurial.

## Global Constraints

- **Version control is Mercurial (`hg`), not git.** There is no `.git` directory. `git` commands will fail.
- **`hg commit` must always name explicit files.** The repo routinely carries unrelated dirty changes. Never run a bare `hg commit`.
- **Commit messages lead with WHY.** First paragraph = the problem or motivation. Bullets = what changed. This is the project's top commit rule.
- **Intranet-only.** No CDN links, no external URLs in served pages.
- **Home performs no queries.** No counts, no freshness data, no `.count` calls in the controller or view.
- **Badges must use a named semantic `.badge-*` class**, never raw `bg-*`. (No badges are added by this plan, but do not introduce any.)
- **Icons are Material Symbols**, rendered via the `resource_icon(key)` helper. The key must exist in `ApplicationHelper::RESOURCE_ICONS`.
- **Do not modify `Reports::Catalog`.** Part 1's taxonomy is fixed. Home consumes it read-only.
- Run tests with `bin/rails test` (unit/controller) and `bin/rails test:system` (system).

---

## File Structure

**Created:**
- `app/services/navigation.rb` — `Navigation::AREAS`, the single source for entity/tool areas on home. Sits beside `app/services/reports/` and `app/services/chulabooster.rb`, matching where this app keeps non-AR domain objects.
- `app/helpers/navigation_helper.rb` — one method, `navigation_area_path(area)`, resolving an area's `path_helper` symbol.
- `app/controllers/home_controller.rb` — root controller, no queries.
- `app/views/home/index.html.haml` — the launchpad, five bands.
- `test/services/navigation_test.rb`
- `test/controllers/home_controller_test.rb`
- `test/integration/navigation_parity_test.rb`
- `test/system/home_test.rb`

**Modified:**
- `config/routes.rb:91` — `root "users#index"` → `root "home#index"`
- `app/controllers/users_controller.rb:3` (before_action) and `:62-66` (`require_admin`) — gate `index`, add admin-or-self for `show`, retarget the redirect
- `app/views/layouts/application.html.haml:63-66` — move the Users nav item into the admin block
- `test/controllers/users_controller_test.rb` — rewrite nine tests to the new contract

**Deliberately untouched:** the sidebar's rendering approach, the eight per-controller `require_admin` copies, `Reports::Catalog`.

---

### Task 1: `Navigation::AREAS` and its path helper

**Files:**
- Create: `app/services/navigation.rb`
- Create: `app/helpers/navigation_helper.rb`
- Test: `test/services/navigation_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Navigation::AREAS` — a frozen `Array` of frozen `Hash`es, each with keys `:key` (String), `:label` (String), `:description` (String), `:path_helper` (Symbol), `:group` (Symbol, one of `:records`, `:teaching_setup`, `:admin`, `:account`), `:access` (Symbol, `:all` or `:admin`). Also `Navigation.for_group(group)` → `Array<Hash>` and `Navigation.visible_to(areas, admin:)` → `Array<Hash>`. And `NavigationHelper#navigation_area_path(area)` → String URL.

- [ ] **Step 1: Write the failing test**

Create `test/services/navigation_test.rb`:

```ruby
require "test_helper"

class NavigationTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  test "every area declares the full set of keys" do
    Navigation::AREAS.each do |area|
      assert_equal %i[key label description path_helper group access].sort,
                   area.keys.sort,
                   "#{area[:label]} has the wrong keys"
    end
  end

  test "every path_helper resolves to a route" do
    Navigation::AREAS.each do |area|
      assert_respond_to self, area[:path_helper],
                        "#{area[:label]} names a route helper that does not exist"
      assert_nothing_raised { public_send(area[:path_helper]) }
    end
  end

  test "every key has a Material Symbols icon" do
    Navigation::AREAS.each do |area|
      assert ApplicationHelper::RESOURCE_ICONS.key?(area[:key]),
             "#{area[:label]} has no RESOURCE_ICONS entry for #{area[:key].inspect}"
    end
  end

  test "groups and access use only the permitted values" do
    Navigation::AREAS.each do |area|
      assert_includes %i[records teaching_setup admin account], area[:group]
      assert_includes %i[all admin], area[:access]
    end
  end

  test "every admin-group area is admin access" do
    Navigation.for_group(:admin).each do |area|
      assert_equal :admin, area[:access], "#{area[:label]} is in :admin but open to all"
    end
  end

  test "for_group preserves declaration order" do
    labels = Navigation.for_group(:records).map { |a| a[:label] }
    assert_equal ["Programs", "Courses", "Staff", "Students", "Grades"], labels
  end

  test "visible_to hides admin areas from non-admins" do
    admin_areas = Navigation.visible_to(Navigation::AREAS, admin: true)
    viewer_areas = Navigation.visible_to(Navigation::AREAS, admin: false)

    assert_includes admin_areas.map { |a| a[:label] }, "Imports"
    assert_not_includes viewer_areas.map { |a| a[:label] }, "Imports"
    assert_includes viewer_areas.map { |a| a[:label] }, "Students"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/navigation_test.rb`
Expected: FAIL — `NameError: uninitialized constant Navigation`

- [ ] **Step 3: Write the implementation**

Create `app/services/navigation.rb`:

```ruby
# Single source of truth for the entity and tool areas listed on the home
# launchpad (app/views/home/index.html.haml).
#
# The sidebar in app/views/layouts/application.html.haml lists the same
# destinations but is NOT driven from here, deliberately: it renders live badge
# counts (LineContact.count, ApiEvent.errors_since) and matches active state
# across multiple controllers (%w[program_groups programs]). Encoding that here
# would mean lambdas and controller-arrays for the benefit of one caller. The
# duplication is guarded by test/integration/navigation_parity_test.rb, which
# fails if a sidebar destination is missing from home.
#
# Reports are NOT listed here — they come from Reports::Catalog.
module Navigation
  # :key         — ApplicationHelper::RESOURCE_ICONS key, for resource_icon
  # :path_helper — zero-argument route helper, resolved with public_send
  # :group       — which band on home: :records, :teaching_setup, :admin, :account
  # :access      — :all or :admin
  AREAS = [
    # --- Records: the "look something up" destinations ---
    { key: "program_groups", label: "Programs", group: :records, access: :all,
      path_helper: :program_groups_path,
      description: "Curricula and their revisions, with course requirements." }.freeze,
    { key: "courses", label: "Courses", group: :records, access: :all,
      path_helper: :courses_path,
      description: "Course catalogue across curriculum revisions." }.freeze,
    { key: "staffs", label: "Staff", group: :records, access: :all,
      path_helper: :staffs_path,
      description: "Lecturers and their teaching assignments." }.freeze,
    { key: "students", label: "Students", group: :records, access: :all,
      path_helper: :students_path,
      description: "Student records, transcripts and course history." }.freeze,
    { key: "grades", label: "Grades", group: :records, access: :all,
      path_helper: :grades_path,
      description: "Enrolment and grade rows by term." }.freeze,

    # --- Teaching setup: the data the schedule reports read from ---
    { key: "semesters", label: "Semesters", group: :teaching_setup, access: :all,
      path_helper: :semesters_path,
      description: "Terms, course offerings, sections and time slots." }.freeze,
    { key: "rooms", label: "Rooms", group: :teaching_setup, access: :all,
      path_helper: :rooms_path,
      description: "Teaching rooms and their capacity." }.freeze,
    { key: "scrapes", label: "Scraper", group: :teaching_setup, access: :all,
      path_helper: :scrapes_path,
      description: "Pull schedule data from the registrar's site." }.freeze,

    # --- Administration: system operation, admin-only ---
    { key: "users", label: "Users", group: :admin, access: :admin,
      path_helper: :users_path,
      description: "Accounts, roles and LLM settings." }.freeze,
    { key: "data_imports", label: "Imports", group: :admin, access: :admin,
      path_helper: :data_imports_path,
      description: "CSV and Excel uploads, with column mapping." }.freeze,
    { key: "data_sources", label: "Data Sources", group: :admin, access: :admin,
      path_helper: :data_sources_path,
      description: "Where each kind of data comes from, and how complete it is." }.freeze,
    { key: "api_events", label: "API Events", group: :admin, access: :admin,
      path_helper: :api_events_path,
      description: "External API calls and their failures." }.freeze,
    { key: "chats", label: "Chat Playground", group: :admin, access: :admin,
      path_helper: :chat_path,
      description: "Try the assistant against live data." }.freeze,
    { key: "chat_messages", label: "Chat History", group: :admin, access: :admin,
      path_helper: :chat_messages_path,
      description: "Past assistant conversations and their tool calls." }.freeze,
    { key: "line_contacts", label: "LINE Contacts", group: :admin, access: :admin,
      path_helper: :line_contacts_path,
      description: "Unlinked LINE users waiting for an account." }.freeze,
    { key: "dev", label: "Style Guide", group: :admin, access: :admin,
      path_helper: :dev_styleguide_path,
      description: "Colour playground and component reference." }.freeze,

    # --- Your account: personal settings, not domain data ---
    { key: "line_accounts", label: "LINE Account", group: :account, access: :all,
      path_helper: :line_account_path,
      description: "Link your LINE account so the bot can answer as you." }.freeze
  ].freeze

  module_function

  def for_group(group)
    AREAS.select { |a| a[:group] == group }
  end

  def visible_to(areas, admin:)
    admin ? areas : areas.reject { |a| a[:access] == :admin }
  end
end
```

Create `app/helpers/navigation_helper.rb`:

```ruby
module NavigationHelper
  # Areas declare a zero-argument route helper symbol; resolve it here so the
  # view never calls public_send directly.
  def navigation_area_path(area)
    public_send(area[:path_helper])
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/navigation_test.rb`
Expected: PASS — 7 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit**

```bash
hg add app/services/navigation.rb app/helpers/navigation_helper.rb test/services/navigation_test.rb
hg commit app/services/navigation.rb app/helpers/navigation_helper.rb test/services/navigation_test.rb -m "The sidebar's destinations exist only as hardcoded HAML

The home launchpad needs the same list of entity and tool areas the sidebar
shows, plus a sentence describing each one. There is no data behind the sidebar
to read - it is 25 lines of repeated link_to - so a second surface would mean a
second hardcoded list and guaranteed drift.

- Add Navigation::AREAS: key, label, description, path_helper, group, access
- Add NavigationHelper#navigation_area_path to resolve the helper symbol
- Tests assert every path_helper routes and every key has an icon, so a typo
  fails here rather than 500ing the root page

The sidebar is deliberately not driven from this constant; see the comment in
navigation.rb for why, and the parity test that guards the duplication instead.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Home controller, route, and view

**Files:**
- Create: `app/controllers/home_controller.rb`
- Create: `app/views/home/index.html.haml`
- Modify: `config/routes.rb:91`
- Test: `test/controllers/home_controller_test.rb`

**Interfaces:**
- Consumes: `Navigation::AREAS`, `Navigation.for_group`, `Navigation.visible_to`, `NavigationHelper#navigation_area_path` (Task 1); `Reports::Catalog.hub_entries`, `Reports::Catalog.grouped`, `Reports::Catalog::SECTIONS`, `ReportsHelper#catalog_report_path` (already in the codebase).
- Produces: `root_path` renders `home#index`. `@report_sections` (Hash of `section_key => Array<Reports::CatalogEntry>`) is available to the view.

**Note:** `ReportsHelper` and `NavigationHelper` are both available in this view — Rails includes all helpers in all views by default (`include_all_helpers` is on). Do not add an `include`.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/home_controller_test.rb`:

```ruby
require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def login(user)
    post login_path, params: { username: user.username, password: "password123" }
  end

  test "root renders the launchpad for a non-admin" do
    login users(:viewer)
    get root_path
    assert_response :success
    assert_select "h6", text: /\ARecords\z/i
  end

  test "root requires login" do
    get root_path
    assert_redirected_to login_path
  end

  test "the launchpad links every non-admin area" do
    login users(:viewer)
    get root_path
    assert_select "a[href=?]", students_path
    assert_select "a[href=?]", semesters_path
    assert_select "a[href=?]", line_account_path
  end

  test "the administration band is admin-only" do
    login users(:viewer)
    get root_path
    assert_select "h6", text: /\AAdministration\z/i, count: 0
    assert_select "a[href=?]", data_imports_path, count: 0

    login users(:admin)
    get root_path
    assert_select "h6", text: /\AAdministration\z/i
    assert_select "a[href=?]", data_imports_path
  end

  test "reports come from the catalog rather than a hardcoded list" do
    login users(:viewer)
    get root_path
    # One report from each of the four hub sections.
    assert_select "a[href=?]", schedules_room_path
    assert_select "a[href=?]", schedules_teaching_matrix_path
    assert_select "a[href=?]", report_path("failing_students")
    assert_select "a[href=?]", report_path("cohort_gpa")
  end

  test "the admin-only data coverage report is not listed on the launchpad" do
    login users(:admin)
    get root_path
    assert_select "a[href=?]", report_path("data_coverage"), count: 0
  end

  test "the reports band links to the hub itself" do
    login users(:viewer)
    get root_path
    assert_select "a[href=?]", reports_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: FAIL — the root still routes to `users#index`, so the `Records` heading assertion fails.

- [ ] **Step 3: Change the route**

In `config/routes.rb`, replace line 91:

```ruby
  root "home#index"
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/home_controller.rb`:

```ruby
# The launchpad at /. Deliberately queryless: it maps the app and links one
# level deeper than the 250px sidebar can, and it holds no counts or freshness
# data, so it cannot go stale or slow. Data-state questions live on
# /data_sources instead.
class HomeController < ApplicationController
  def index
    @report_sections = Reports::Catalog.grouped
  end
end
```

- [ ] **Step 5: Write the view**

Create `app/views/home/index.html.haml`:

```haml
-# The home launchpad. Areas come from Navigation::AREAS, reports from
-# Reports::Catalog - never hardcode either list here.
-# Reports render as link lists, not cards: with 14 of them, card treatment
-# swamps the entity bands and makes this page a near-copy of the hub.

- areas_band = ->(title, group) do
  - areas = Navigation.visible_to(Navigation.for_group(group), admin: current_user.admin?)
  - next if areas.empty?
  .mb-4
    %h6.text-uppercase.text-body-secondary.small.fw-semibold.mb-2= title
    .row.g-3
      - areas.each do |area|
        .col-md-4
          = link_to navigation_area_path(area), class: "card h-100 text-decoration-none" do
            .card-body
              %h6.card-title.mb-1.d-flex.align-items-center
                = resource_icon(area[:key])
                = area[:label]
              %p.small.text-body-secondary.mb-0= area[:description]

.card
  .card-body.p-3
    = areas_band.call("Records", :records)
    = areas_band.call("Teaching setup", :teaching_setup)

    .mb-4
      %h6.text-uppercase.text-body-secondary.small.fw-semibold.mb-2
        = link_to "Reports", reports_path, class: "text-decoration-none text-reset"
      %p.small.text-body-secondary.mb-3 Read-only analyses across students, courses and teaching.
      - @report_sections.each do |section_key, entries|
        .mb-3
          %p.small.fw-semibold.mb-1= Reports::Catalog::SECTIONS[section_key]
          .d-flex.flex-wrap.column-gap-4.row-gap-1
            - entries.each do |entry|
              = link_to entry.title, catalog_report_path(entry), class: "small text-decoration-none"

    = areas_band.call("Your account", :account)
    -# Profile is not in Navigation::AREAS: its path needs current_user, and
    -# every other area uses a zero-argument route helper. One special case
    -# here beats a second way of expressing paths in the constant.
    .row.g-3.mt-0
      .col-md-4
        = link_to user_path(current_user), class: "card h-100 text-decoration-none" do
          .card-body
            %h6.card-title.mb-1.d-flex.align-items-center
              = resource_icon("users")
              Profile
            %p.small.text-body-secondary.mb-0 Your own account details and LINE link status.

    = areas_band.call("Administration", :admin)
```

**Careful — HAML lambdas.** The `areas_band` lambda uses `- next if areas.empty?` to bail out; `return` would raise `LocalJumpError`. If the lambda form gives trouble, inline the three bands instead of abstracting — correctness beats DRY here, and the plan's tests are the contract, not the implementation shape.

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: PASS — 7 runs, 0 failures, 0 errors

- [ ] **Step 7: Run the full suite to catch collateral damage**

Run: `bin/rails test`
Expected: PASS. The root change touches `test/system/login_test.rb` (asserts `assert_current_path root_path` after sign-in — still true) and the `visit root_path` calls in `data_imports_test.rb` / `data_sources_test.rb` (they assert on `nav a`, which is the sidebar, unaffected). If any of these fail, stop and report rather than editing the assertions.

- [ ] **Step 8: Commit**

```bash
hg add app/controllers/home_controller.rb app/views/home/index.html.haml test/controllers/home_controller_test.rb
hg commit app/controllers/home_controller.rb app/views/home/index.html.haml test/controllers/home_controller_test.rb config/routes.rb -m "Signing in landed you on a table of user accounts

root pointed at users#index, so the first page after login was every account's
username, email, role and LLM settings. It answers a question nobody asked, and
it wasted the URL best placed to fix what Part 1 left behind: the sidebar can
afford one word for fourteen reports, so the reports are still a level too deep.

- Add HomeController#index and point root at it; no queries, so it cannot go
  stale or slow
- Five bands: Records, Teaching setup, Reports, Your account, Administration
- Reports are read from Reports::Catalog, so home and the hub cannot drift, and
  the admin-only Data Coverage report stays off both
- Reports render as grouped links rather than cards; mocked both ways, and 14
  cards swamp the entity bands and duplicate the hub

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Gate Users and move it into the admin nav

**Files:**
- Modify: `app/controllers/users_controller.rb` (lines 3 and 62-66)
- Modify: `app/views/layouts/application.html.haml` (remove lines 63-66; add to the admin block)
- Test: `test/controllers/users_controller_test.rb` (rewrite nine tests)

**Interfaces:**
- Consumes: `root_path` now renders home (Task 2) — this is what makes it a sane denial target.
- Produces: `/users` is admin-only. `/users/:id` is admin-or-self. All `UsersController` denials redirect to `root_path` with `"Only admins can perform this action."`

**Why the redirect target must change:** `UsersController#require_admin` currently redirects to `users_path`. Once `index` is gated, a non-admin hitting `/users` is redirected to `/users`, which redirects to `/users` — `ERR_TOO_MANY_REDIRECTS`. This is not cosmetic.

- [ ] **Step 1: Rewrite the failing tests**

In `test/controllers/users_controller_test.rb`, replace the two tests at lines 8-16 with:

```ruby
  test "non-admin cannot view index" do
    get users_path
    assert_redirected_to root_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin can view their own profile" do
    get user_path(users(:viewer))
    assert_response :success
  end

  test "non-admin cannot view another user's profile" do
    get user_path(users(:admin))
    assert_redirected_to root_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "admin can view any profile" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get user_path(users(:viewer))
    assert_response :success
  end
```

Then change every remaining `assert_redirected_to users_path` in this file to `assert_redirected_to root_path`. They appear in `"non-admin cannot access new"`, `"non-admin cannot create"`, `"non-admin cannot access edit"`, `"non-admin cannot update"`, `"non-admin cannot delete"`, `"non-admin cannot generate line code"` and `"non-admin cannot unlink line"`. Verify with `grep -n "users_path" test/controllers/users_controller_test.rb` — the rule is that **no** `assert_redirected_to users_path` remains.

Do **not** weaken or delete any assertion beyond these redirect targets. The `"Only admins can perform this action."` flash text is unchanged.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/users_controller_test.rb`
Expected: FAIL — `"non-admin cannot view index"` gets a 200 instead of a redirect; the profile tests fail similarly.

- [ ] **Step 3: Gate the controller**

In `app/controllers/users_controller.rb`, change the before_action on line 3 and add the self-or-admin check. The `before_action` block becomes:

```ruby
  before_action :set_user, only: %i[show edit update destroy generate_line_code unlink_line]
  before_action :require_admin, only: %i[index new create edit update destroy generate_line_code unlink_line]
  before_action :require_admin_or_self, only: %i[show]
```

Replace the private `require_admin` (lines 62-66) with:

```ruby
  # Redirects to root_path, not users_path: index is admin-gated, so pointing a
  # denied non-admin back at /users would loop.
  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end

  # A lecturer reaches their own record via the sidebar's Profile link, but has
  # no reason to enumerate colleagues' roles and LLM settings.
  def require_admin_or_self
    unless current_user.admin? || current_user == @user
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/users_controller_test.rb`
Expected: PASS — 0 failures, 0 errors

- [ ] **Step 5: Move the sidebar item**

In `app/views/layouts/application.html.haml`, delete the Users `%li.nav-item` block (currently lines 63-66):

```haml
          %li.nav-item
            = link_to users_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'users'}" do
              = resource_icon("users")
              Users
```

Add the same block inside the `- if current_user.admin?` section, as the first item after the `Admin` heading `%li` (i.e. immediately before the Chat Playground item):

```haml
            %li.nav-item
              = link_to users_path, class: "nav-link d-flex align-items-center #{'active' if controller_name == 'users'}" do
                = resource_icon("users")
                Users
```

Note the indentation increases by two spaces — it is now nested inside the admin conditional.

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test && bin/rails test:system`
Expected: PASS. If a system test fails on a missing "Users" nav link for a non-admin, that test was asserting the old contract — report it rather than silently changing it.

- [ ] **Step 7: Commit**

```bash
hg commit app/controllers/users_controller.rb app/views/layouts/application.html.haml test/controllers/users_controller_test.rb -m "Users presented account admin as though it were a domain entity

Users sat in the main sidebar nav beside Programs, Courses and Students, and
index and show were open to every logged-in user. With one login that is
invisible; it stops being invisible the moment lecturers get accounts and the
default landing page is a roster of everyone's email, role and LLM settings.

- Gate index behind require_admin; move the nav item into the admin block
- show becomes admin-or-self, so the sidebar's Profile link still works
- Retarget UsersController#require_admin from users_path to root_path

That last one is required, not cosmetic: gating index while the denial still
redirected to users_path would send a non-admin from /users to /users to /users.
root_path only became a sane denial target now that it renders the launchpad
rather than the very list the user was denied.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Parity test and system test

**Files:**
- Create: `test/integration/navigation_parity_test.rb`
- Create: `test/system/home_test.rb`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing consumed downstream. This task closes the loop on the "no sidebar refactor" decision.

- [ ] **Step 1: Write the parity test**

Create `test/integration/navigation_parity_test.rb`:

```ruby
require "test_helper"

# The sidebar (app/views/layouts/application.html.haml) and the home launchpad
# (Navigation::AREAS + Reports::Catalog) are two hardcoded lists of the same
# destinations. Driving both from one constant was considered and rejected - the
# sidebar renders live badge counts and multi-controller active states, which
# would need lambdas in the constant for the benefit of one caller.
#
# This test is what makes that duplication safe: add a sidebar item and forget
# home, and this fails.
class NavigationParityTest < ActionDispatch::IntegrationTest
  # Links that belong to the sidebar chrome and have no place on home.
  SIDEBAR_ONLY = [
    "/",  # the CP API brand link, which points at home itself
    "#"   # the account dropdown toggle
  ].freeze

  test "every sidebar destination also appears on the launchpad" do
    # Must run as an admin: a viewer's sidebar omits the whole admin block, so a
    # viewer session would never exercise the full nav and this would pass vacuously.
    post login_path, params: { username: users(:admin).username, password: "password123" }
    get root_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    sidebar_hrefs = doc.css("nav#sidebar a[href]").map { |a| a["href"] }.uniq - SIDEBAR_ONLY
    main_hrefs = doc.css("main a[href]").map { |a| a["href"] }.uniq

    assert sidebar_hrefs.any?, "found no sidebar links - the selector is wrong"

    missing = sidebar_hrefs - main_hrefs
    assert_empty missing,
                 "these sidebar destinations are missing from the home launchpad: " \
                 "#{missing.join(', ')}. Add them to Navigation::AREAS (or to " \
                 "SIDEBAR_ONLY if they are deliberately chrome-only)."
  end
end
```

- [ ] **Step 2: Run the parity test**

Run: `bin/rails test test/integration/navigation_parity_test.rb`
Expected: PASS.

If it fails listing a real destination, add that area to `Navigation::AREAS` — do **not** widen `SIDEBAR_ONLY` to make it green. `SIDEBAR_ONLY` is only for chrome (the brand link and the dropdown toggle).

- [ ] **Step 3: Write the system test**

Create `test/system/home_test.rb`:

```ruby
require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  def login_as(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "signing in lands on the launchpad" do
    login_as users(:viewer)

    assert_current_path root_path
    # Band headings are uppercased by CSS, so Selenium reads them uppercase.
    assert_selector "h6", text: /\ARecords\z/i
    assert_selector "h6", text: /\AReports\z/i
    assert_link "Students"
  end

  test "a report on the launchpad opens that report" do
    login_as users(:viewer)

    # Scope to main: the sidebar links some of the same destinations, and an
    # unscoped click_on raises Capybara::Ambiguous.
    within("main") { click_on "Teaching Matrix" }
    assert_current_path schedules_teaching_matrix_path
  end

  test "an entity area on the launchpad opens that area" do
    login_as users(:viewer)

    within("main") { click_on "Semesters" }
    assert_current_path semesters_path
  end

  test "a non-admin sees no Users link in the sidebar" do
    login_as users(:viewer)

    assert_no_selector "nav#sidebar a", text: "Users"
    assert_selector "nav#sidebar a", text: "Students"
  end

  test "an admin sees Users in the sidebar admin block" do
    login_as users(:admin)

    assert_selector "nav#sidebar a", text: "Users"
  end
end
```

- [ ] **Step 4: Run the system test**

Run: `bin/rails test:system test/system/home_test.rb`
Expected: PASS — 5 runs, 0 failures, 0 errors

**Note on `resource_icon`:** it renders the Material Symbols glyph name as element text (`<span class="material-symbols">school</span>`), so a card's `h6` reads as `"schoolStudents"`, not `"Students"`. Capybara's `assert_link`/`click_on` do substring matching, so the tests above work — but an exact-text assertion on a card title will not. Use substring or regex matching for card titles.

- [ ] **Step 5: Run the whole suite**

Run: `bin/rails test && bin/rails test:system`
Expected: PASS, 0 failures, 0 errors across both. Report the actual counts.

- [ ] **Step 6: Commit**

```bash
hg add test/integration/navigation_parity_test.rb test/system/home_test.rb
hg commit test/integration/navigation_parity_test.rb test/system/home_test.rb -m "Nothing stopped the sidebar and the launchpad from drifting apart

The sidebar and home list the same destinations from two hardcoded sources.
Unifying them was rejected on purpose - the sidebar needs live badge counts and
multi-controller active states that would have to become lambdas in a shared
constant, for one caller's benefit. That decision is only safe if forgetting to
update home fails loudly.

- Add a parity test asserting every sidebar href appears inside <main>, with a
  two-entry allowlist for chrome (brand link, dropdown toggle)
- It runs as an admin on purpose: a viewer's sidebar omits the admin block, so a
  viewer session would pass vacuously
- Add system coverage for landing on the launchpad, clicking through to a report
  and an entity area, and Users being admin-only in the nav

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation

Per `CLAUDE.md`, `docs/backlog.md` holds recurring items with explicit triggers, and adding or changing a report or an entity show page triggers a review of them. This plan adds neither — it adds a navigation surface — but open `docs/backlog.md` and confirm nothing there is triggered before calling the work done.

Also confirm the four-item checklist from the spec's Goals section:

- [ ] Root is a launchpad, not a user roster
- [ ] Reports on home derive from `Reports::Catalog` (verified by the catalog test in Task 2)
- [ ] Users is admin-gated and out of the domain nav
- [ ] The sidebar/home duplication is guarded by a failing-on-drift test
