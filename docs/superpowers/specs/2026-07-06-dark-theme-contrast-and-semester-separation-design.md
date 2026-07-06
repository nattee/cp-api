# Dark Theme Contrast + Course History Semester Separation

**Date:** 2026-07-06
**Status:** Approved (brainstormed with visual mockups on live page, student 3040)

## Problem

Two related pains on `/students/:id` (and app-wide):

1. **Semester/group boundaries are invisible in Course History.** The
   `.table-group-header` rows use a 3% white tint (`rgba(white, 0.03)`) on a
   near-black page, with text *smaller* (0.85rem) than the data rows. With 15+
   semesters the table reads as one undifferentiated stream.
2. **All surfaces melt together ("samey/flat").** `$card-bg` is
   `rgba(#101828, 0.6)`, which composites to rgb(11,16,31) — 8–13 RGB points
   above the rgb(3,7,18) page canvas. Cards, page, and sidebar are visually
   one surface. Going opaque roughly doubles the separation (rgb(16,24,40)).
   Cards already have Bootstrap's default dark-mode 1px border
   (rgba(255,255,255,0.15)); it stays untouched — an added custom border at
   rgba(white,0.08) was mocked up and **measured dimmer than the existing
   default** (edge brightness 44 vs 60), i.e. a downgrade, caught during
   review (rendered screenshots, 2026-07-06).

A light/dark theme toggle was considered and **explicitly rejected**: the
user's pains are boundary-visibility and surface flatness, both fixable
in-theme. The palette family itself (blue-slate + cyan/pink/violet accents)
was audited and judged sound. Revisit only if dark-background eye strain
becomes a real complaint.

## Decisions (validated against rendered mockups)

| # | Decision | Chosen over |
|---|----------|-------------|
| 1 | Gap-separated semester blocks (spacer rows) **plus** accent band headers | gaps-only, bands-only, zebra striping, sticky headers |
| 2 | Header band background stays **neutral** `rgba(white, 0.05)` | primary-tinted band (reads as "selected row"), opaque slab (all three nearly indistinguishable at 2x zoom; neutral matches existing `rgba(white, x)` convention) |
| 3 | `$card-bg` becomes **opaque `#101828`**; card border **unchanged** (Bootstrap dark default rgba(255,255,255,0.15) already present) | translucent bg with stronger tint; custom rgba(white,0.08) border (measured dimmer than the default it would replace); full palette revisit |
| 4 | Body text softens `#ffffff` → `#e6edf3` (GitHub dark text) | keeping pure white (max contrast everywhere = glare, no emphasis headroom) |

## Changes

### 1. View: `app/views/students/show.html.haml`

In **both** Course History tabs (By Course Group, By Semester): insert a
spacer row before each group header **except the first**:

```haml
- grouped.each_with_index do |(group_name, group_grades), idx|
  - if idx.positive?
    %tr.table-group-spacer
      %td{colspan: 6}
  %tr.table-group-header
    ...
```

This is the only view using `.table-group-header` today.

### 2. SCSS: `app/assets/stylesheets/application.scss`

**Pre-import variable changes:**

```scss
$body-color-dark: #e6edf3;            // was #ffffff — soft white, reduces glare, frees pure white for emphasis
$card-bg:         #101828;            // was rgba(#101828, 0.6) — opaque so cards separate from the #030712 canvas
```

Do **not** set `$card-border-color`: the dark-mode default
(`rgba(255,255,255,0.15)` via `$border-color-translucent`) is already the
strongest edge in play.

**Post-import rule changes** (existing `.table-group-header` block):

```scss
.table-group-header td {
  background-color: rgba(white, 0.05);           // was 0.03 — now a visible band
  border-top: 1px solid $table-head-border-color;
  box-shadow: inset 3px 0 0 $primary;            // cyan accent bar; shadow not border so columns don't shift
  font-size: 0.95rem;                            // was 0.85rem — header now larger than data rows
  padding-top: 0.65rem;
  padding-bottom: 0.5rem;
}
.table-group-header strong { color: $light; letter-spacing: 0.02em; }

// Spacer rows create a gap of card background between groups
.table-group-spacer td {
  padding: 0.7rem 0;
  border: 0;
  background: transparent;
}
// Suppress .table-hover highlight on spacers — an empty row must not light up.
// Must match Bootstrap's `.table-hover > tbody > tr:hover > *` specificity, so
// a bare `.table-group-spacer td { box-shadow: none }` is NOT enough.
.table-hover > tbody > tr.table-group-spacer:hover > td { box-shadow: none; }
```

The existing first-child rule (no top border on the first group header) stays.

### 3. Documentation

- `docs/shadcn-color-mapping.md`: update the `$card-bg` entry (opaque, no
  longer `/ 0.6` alpha) and note the `$body-color-dark` deviation with
  rationale.
- `CLAUDE.md` "Table group headers" bullet: add the spacer-row pattern
  (`%tr.table-group-spacer` between groups) so future group tables follow it.

## Out of Scope

- Light/dark toggle (rejected above).
- Palette changes beyond the three variables listed.
- Muted-text contrast (user explicitly did not report it as a pain).
- Group-header hover behavior (unchanged from today).

## Verification

- `bin/rails dartsass:build`, then visual check of `/students/3040`: both
  Course History tabs show gap + banded headers; cards visibly lift off the
  page everywhere (index pages, forms, style guide).
- Existing test suite passes (`bin/rails test`, `bin/rails test:system`).
  No new tests planned — visual-only change; per project convention, ask
  before writing any.
- The `/dev/styleguide` Color Playground still reflects reality (it reads the
  compiled variables; spot-check card/table samples).

## Risks

- `$card-bg` opacity affects **every** card in the app; the mockup validated
  the student page and the change is strictly "more separation", but a quick
  scan of index pages and the login card is part of verification.
- `$body-color-dark` propagates through Bootstrap CSS vars; 3rd-party
  override blocks that hardcode `#fff` equivalents (Select2, Flatpickr,
  DataTables) are unaffected by design — they don't read the variable — so
  no vendor churn is expected.
