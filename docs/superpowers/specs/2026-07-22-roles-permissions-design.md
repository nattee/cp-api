# Roles & Permissions System — Design

**Date**: 2026-07-22
**Status**: Approved

## Problem

Every logged-in user can currently read everything, including grades. The `role`
string column (`admin`/`editor`/`viewer`) only gates writes (`admin?`); `editor`
is defined but never checked anywhere. New user populations need scoped read
access:

- **Public-info users** (e.g. students reached via LINE): data that is public by
  nature — course offerings, sections, schedules, basic course info (mostly
  scraped from public sites anyway). No student data.
- **Minimal student access**: look up any student's identity + program +
  admission year. No status, no enrollments, no grades.
- **Advisors**: lecturers who additionally get *full* access (including grades)
  to their own advisees, while keeping only their base access for everyone else.

Roles and permissions will change in the future, so re-bundling permissions must
be an admin-UI action, not a deploy.

## Core concepts

- **Permission** = one atomic, checkable capability. Each corresponds to
  enforcement code (a `before_action`, a view conditional, a LINE tool gate).
  The catalog is a **frozen constant in code** — honest about reality, since a
  new permission always needs new enforcement code anyway.
- **Role** = a named bundle of permissions, stored in the **DB** and editable by
  admins. Roles form a **DAG** via inheritance edges: a role's effective
  permissions = its own grants ∪ all ancestors' effective permissions.
- **Advisor is not a role.** `advisees.read_full` is a *scoped* permission that
  self-activates only for users who actually have current `advisorships` rows.
  It sits in the staff bundle; lecturers with no advisees get nothing extra from
  it. Becoming an advisor = recording the advisorship, no role change.
- **One role per user.** Odd combinations are handled by composing a new role in
  the UI (inherit from several parents) — cheap because roles are data.

## Permission catalog

```ruby
Permission::CATALOG = {
  "courses.read"          => "Course offerings, sections, schedules, basic course info",
  "students.read_minimal" => "Any student: ID, name, program, admission year",
  "students.read_full"    => "Any student: everything incl. status & course history",
  "grades.read"           => "Grade values, GPA, distributions (any student)",
  "advisees.read_full"    => "Own advisees only: everything incl. grades",
  "users.manage"          => "Admin: manage users, roles, imports, all writes"
}.freeze
```

Notes:

- `students.read_full` says nothing about grades; grade values are exclusively
  behind `grades.read` (global) or `advisees.read_full` (scoped).
- `students.read_minimal` limits **fields, not rows**: minimal users can browse
  and search the *full* roster, seeing only identity/program/year columns.
- Not an ActiveRecord model — `Permission` is a plain module holding the catalog
  and lookup helpers.

## Data model

### `roles` table

| column            | type    | notes                                             |
| ----------------- | ------- | ------------------------------------------------- |
| `name`            | string  | unique, e.g. `admin`, `staff`, `minimal`, `public-info` |
| `description`     | string  |                                                   |
| `permission_keys` | json    | array of catalog keys; validated against catalog  |
| `locked`          | boolean | seeded admin role: undeletable, uneditable        |

### `role_inheritances` table

`role_id`, `parent_role_id` — the DAG edges. Unique pair index. Cycle
validation on save. Effective permissions computed by walking ancestors
(memoized per request).

### `users` changes

- Add `role_id` FK (`null: false` after backfill); **drop the `role` string
  column in the same migration** (add → seed roles → map strings → drop). The
  two columns never coexist in the running app.
- Add `staff_id` (nullable FK) — links a login account to its Staff record;
  this is how the app resolves *whose* advisees a user gets.
- Migration mapping: `admin` → admin role; `editor` and `viewer` → staff role
  (all current users are department insiders; nobody loses access).
- New-user default role: **public-info** (least privilege) — replaces today's
  `viewer` default. The LINE quick-link "Create & Link" flow creates users with
  this default.

### Seeded roles

| role          | own grants                                                              | inherits     |
| ------------- | ----------------------------------------------------------------------- | ------------ |
| `public-info` | `courses.read`                                                          | —            |
| `minimal`     | `students.read_minimal`                                                 | public-info  |
| `staff`       | `students.read_full`, `grades.read`, `advisees.read_full`               | minimal      |
| `admin`       | all catalog keys (locked)                                               | —            |

### `advisorships` table

| column       | type   | notes                                  |
| ------------ | ------ | -------------------------------------- |
| `student_id` | FK     |                                        |
| `staff_id`   | FK     |                                        |
| `started_on` | date   |                                        |
| `ended_on`   | date   | null = current                         |
| `note`       | string |                                        |

Overlapping rows allowed (co-advisors, grad programs), but no duplicate
*active* row for the same (student, staff) pair — enforced by validation.
Current advisees = `ended_on IS NULL`. History preserved on reassignment (set
`ended_on`, add new row).

## Enforcement architecture

### Core resolver

- `user.can?("grades.read")` — membership in the role's effective
  (DAG-expanded, per-request-memoized) permission set.
- `user.advisee_ids` — current advisee student IDs via
  `staff → advisorships (ended_on IS NULL)`; empty when `staff_id` is nil.
- Composite helpers (single source of truth for scoped logic):
  - `user.can_view_student_fully?(student)` =
    `students.read_full` ∨ (`advisees.read_full` ∧ student is advisee)
  - `user.can_view_grades?(student)` =
    `grades.read` ∨ (`advisees.read_full` ∧ student is advisee)
- `user.admin?` becomes `can?("users.manage")` — existing view checks
  (`current_user.admin?`) keep working, and admin-equivalent custom roles work
  too. `require_admin_or_self` in UsersController keeps its semantics.

### Web UI

- `ApplicationController#require_permission(key)` generalizes `require_admin`;
  `require_admin` stays as a thin alias for `require_permission("users.manage")`
  so existing controllers don't churn.
- Read gates: courses/course_offerings/semesters/rooms/schedules →
  `courses.read`; students → `students.read_minimal` minimum; grades →
  `grades.read`. Reports gate per report: schedule reports (room, staff,
  workload, curriculum, conflicts, teaching matrix) → `courses.read`;
  grade-bearing reports (grade distribution, data coverage, anything showing
  GPA or grade values) → `grades.read`.
- `students#show` renders in tiers: identity/program/year card for minimal
  users; status, course history, and grade sections only when the composite
  helpers allow.
- `students#index` hides the status column for minimal-only users.
- Sidebar nav entries render only when the user holds that resource's read
  permission (one key per entry, driven from the catalog).
- Unauthorized access → redirect with alert, same UX as today's `require_admin`.

### LINE tools — layered gates

```
webhook → MessageRouter (gate 0) → ChatJob → LlmService (gate 1)
        → LLM → ToolCallParser → ToolExecutor (gate 2) → tool body (gate 3)
```

- **Gate 0 — identity/consent (exists today, unchanged)**:
  `MessageRouter.dispatch_to_llm` refuses anyone without a linked, consenting
  account (`user&.llm_consent?`); they become a `LineContact` and never reach
  the LLM. Today linking *is* authorization because all linked users are trusted
  staff. **This feature breaks that equivalence** — public-info students will be
  linked and consenting, so gates 1–3 become necessary.
- **Gate 1 — role-filtered definitions**: each tool declares
  `required_permission` at registration; `ToolRegistry.definitions(user:)`
  filters, so the LLM never sees tools the user can't call. Mostly a
  quality/prompt-size measure; keeps weak local models from attempting doomed
  calls.
- **Gate 2 — executor re-check by tool name**: `ToolExecutor` re-checks
  `required_permission` before dispatch. Catches calls gate 1 can't prevent:
  hallucinated tool calls (local qwen/gemma models emit un-offered tools
  routinely) and history imitation (replayed `ChatMessage` transcripts advertise
  tools the user could call before a role downgrade/edit). Denied calls return a
  plain "not authorized for this data" tool result so the LLM responds
  gracefully.
- **Gate 3 — in-tool scoped checks**: the only place argument-dependent scope
  can be enforced. `student_grades_tool` checks `can_view_grades?(student)` per
  student; `student_lookup_tool` returns the minimal field set unless
  `can_view_student_fully?`. Aggregate tools (cohort GPA/ranking, grade
  distribution, missing enrollments) require `grades.read` outright — aggregates
  leak grades.

## Admin UX

### Roles page (`/roles`, `users.manage` only)

Standard index-card CRUD (Rooms/Programs pattern):

- Form: name, description, checkbox grid of catalog permissions (each with its
  human description), "inherits from" multi-select (cycle-validated).
- Show page: **effective** permission list — own grants plus inherited, labeled
  with which parent contributed them.
- Index: role name, description, user count, permission count.
- Badges: data-driven `"badge-#{role.name.dasherize}"`; SCSS classes for seeded
  roles, generic `.badge-role` frosted fallback for UI-created roles (sane look
  without a deploy).
- User form's role dropdown reads from the DB; also gains a "Staff record"
  Select2 (sets `users.staff_id`).

### Advisorships

- Student show page: Advisor card — current advisor(s) + history; admin
  adds/ends advisorships inline.
- Staff show page: mirror card listing current advisees.
- Bulk load: `AdvisorshipImporter` via the existing import system (CSV: student
  ID, staff name/initials, started_on) — same mapping flow as other importers.

### Provisioning

- Lecturers/staff: manual User creation (as today), now linked to their Staff
  record.
- Students/outsiders: no web accounts; they arrive via LINE and the quick-link
  flow creates their User with the public-info default role. Admin upgrades the
  role afterwards if warranted.

## Edge cases & error handling

- Role deletion is `restrict`-guarded: cannot delete a role that users hold or
  that other roles inherit from (UI shows user count per role).
- The seeded admin role is `locked`: undeletable and uneditable — prevents
  locking yourself out by unchecking `users.manage` on your own role.
- `users.role_id` is `null: false` — no roleless users.
- Ended advisorships grant nothing; overlap is allowed for co-advisors.
- Permission sets memoized per request only — role edits take effect on the
  next request, no cross-request cache to invalidate.
- Inheritance cycles rejected at save time.
- LINE tool denial (gate 2/3) returns a plain error string to the LLM, never an
  exception.

## Testing plan

- **Model**: Role DAG expansion (multi-level inheritance, cycle rejection,
  unknown-key rejection), Advisorship scopes/validations, `User#can?`,
  `advisee_ids`, composite helpers.
- **Integration**: role×controller access matrix — public-info, minimal, staff,
  admin against courses, students, grades, reports, roles.
- **LINE**: registry filtering per role, executor denial, `student_grades_tool`
  advisee scoping, `student_lookup_tool` minimal-vs-full field sets.
- **System**: `students#show` rendered tiers for minimal vs staff vs
  advisor-viewing-advisee; roles CRUD happy path.

Tests are written after the feature is finished (project convention: discuss
scope with the user before writing).

## Out of scope

- Multiple roles per user (a `user_roles` join). The DAG + compose-a-new-role
  covers known combinations; revisit only if a real case appears that
  composition can't express.
- Permission rows in the DB ("fully dynamic"). A permission without enforcement
  code is inert; putting them in the DB adds drift risk for zero deploy savings.
- Student self-service web accounts; LINE remains their interface.
- Backfilling historical advisor data beyond the initial CSV import.
