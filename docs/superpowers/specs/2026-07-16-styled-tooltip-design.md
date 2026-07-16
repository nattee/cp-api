# Styled Instant Tooltips (`data-tooltip`) — Design

**Date**: 2026-07-16
**Status**: Approved (brainstorm with dae)

## Problem

Informational hover text (teaching-history cells on `staffs/show`, the New
Students cohort breakdown on the data-coverage report, the `% ≥ C` header on
grades distribution) uses native `title` tooltips. Two complaints:

1. **Slow** — browsers impose a fixed ~1 s hover delay that cannot be changed.
2. **Unreadable** — the OS tooltip font is tiny and cannot be styled.

Bootstrap tooltips are not an option: Bootstrap's JS is UMD with no ESM
exports and cannot load through our importmap (see CLAUDE.md Asset Pipeline).
A pure-CSS `::after` tooltip also fails here: both target tables sit inside
`.table-responsive` (`overflow-x: auto`), which clips absolutely-positioned
descendants — exactly the top rows (newest terms) where the data-coverage
breakdown cells live.

## Goal

Fast (~100 ms), theme-styled, readable tooltips for **informational hover
text only**, with no vendored library. Icon action buttons (Edit/Delete/Show
ghost buttons) keep native `title` — the icon already conveys the action, so
the native delay doesn't hurt there.

## Non-goals

- Converting icon-button `title` labels app-wide.
- Collision-detection framework (Popper etc.) — a fixed-position flip
  (above → below near viewport top) plus horizontal clamping is enough.
- Touch support beyond what focus already gives (intranet desktop app).

## Design

### Markup contract

- Trigger: plain `data-tooltip="text"` attribute on any element. No per-view
  controller wiring.
- One global controller: `data-controller="tooltip"` on `<body>` in
  `app/views/layouts/application.html.haml` (not the auth layout). The
  controller uses event delegation (`mouseover`/`focusin` →
  `event.target.closest("[data-tooltip]")`), so dynamically inserted content
  (DataTables re-renders) works without re-initialization.

### Controller — `app/javascript/controllers/tooltip_controller.js`

Hand-written, no dependencies, ~40–60 lines:

- Lazily creates a single shared `div.app-tooltip` with `role="tooltip"`,
  appended to `document.body`.
- **Show**: after a 100 ms timer (feels instant vs the native ~1 s, but
  avoids flicker-storms when sweeping across a row of cells). Sets
  `textContent` from `data-tooltip` (never innerHTML — values include
  user-adjacent data).
- **Position**: `position: fixed` (escapes `.table-responsive` clipping),
  horizontally centered above the trigger's `getBoundingClientRect()`;
  flips below when the tooltip would cross the viewport top; clamped to
  viewport edges horizontally.
- **Hide**: mouseleave/blur of the trigger, `Escape`, any scroll (capture
  phase — fixed positioning goes stale on scroll), and `turbo:before-cache`
  (also cancels the pending show timer so no orphan appears post-navigation).
- No-ops gracefully if the trigger or its attribute disappears mid-hover
  (Turbo replace).
- Keyboard: works on naturally focusable triggers (the course links).
  No `tabindex` added to plain `<td>` cells — native `title` had no keyboard
  access either; not a regression.

### Styling — `application.scss`

- `.app-tooltip`: `$popover-bg` background, subtle border
  (`lighten($dark, 18%)`-family), border-radius, small shadow,
  **`font-size: 0.8125rem`** (the readability fix), `white-space: pre-line`
  (the cohort breakdown joins lines with `\n`), `max-width: 320px`,
  `z-index` above all app chrome, `pointer-events: none`.
- Affordance rule: the existing `td[title]` dotted-underline + `cursor: help`
  rule (application.scss ~line 286) is **changed** to
  `td[data-tooltip], th[data-tooltip]` — same look, new attribute, and now
  also marks the `% ≥ C` header. Links keep their own link affordance.

### View / report changes

| File | Change |
|---|---|
| `app/views/staffs/show.html.haml:137` | course link `title:` → `"data-tooltip":` |
| `app/views/staffs/show.html.haml:144` | sections cell `title:` → `"data-tooltip":` |
| `app/views/reports/_result_table.html.haml:44` | `title:` → `"data-tooltip":` in `td_attrs` (+ update the `title_key` comment) |
| `app/views/grades/distribution.html.haml:61` | `%th` `title:` → `"data-tooltip":` |
| `app/views/layouts/application.html.haml` | add `data-controller="tooltip"` to `<body>` |

`Reports::DataCoverage` and the `title_key:` column-spec convention are
untouched — `title_key` remains the row key holding hover text; only the
rendered attribute changes. The `\n`-joined multi-line format keeps working
via `pre-line`.

Empty/nil values never render the attribute (the partial already `.compact`s
`td_attrs`; the HAML nil-attribute caveat documented there applies to
`data-tooltip` the same way).

### Error handling

- Nil/blank tooltip text → attribute absent → controller never triggers.
- Trigger removed from DOM while timer pending → show callback re-checks
  `isConnected` and aborts.

### Verification & testing

- Screenshot comparison (headless Firefox) of both pages with a tooltip
  open, per dae's UI-change review rule, before requesting approval.
- Tests discussed after implementation per project convention; candidate:
  system test hovering a teaching-history cell and a data-coverage breakdown
  cell, asserting `.app-tooltip` becomes visible with the expected text and
  correct multi-line rendering.
