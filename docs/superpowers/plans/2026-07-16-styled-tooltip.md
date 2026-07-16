# Styled Instant Tooltips (`data-tooltip`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace slow, tiny native `title` tooltips on informational hover text with a fast (100 ms), theme-styled tooltip driven by a `data-tooltip` attribute.

**Architecture:** One dependency-free Stimulus controller (`tooltip_controller.js`) attached to `<body>` uses event delegation to show a single shared `position: fixed` div for any `[data-tooltip]` element — fixed positioning escapes `.table-responsive`'s `overflow-x: auto` clipping, which rules out pure-CSS `::after` tooltips on exactly the affected tables. Four view spots convert from `title:` to `data-tooltip`; icon action buttons keep native `title`.

**Tech Stack:** Rails 8.1, HAML, Stimulus (importmap, auto-registered via `eagerLoadControllersFrom`), Dart Sass, Turbo Drive.

**Spec:** `docs/superpowers/specs/2026-07-16-styled-tooltip-design.md`

## Global Constraints

- **Intranet-only**: no CDN or external URLs; no vendored libraries for this feature (hand-written controller only).
- **Turbo Drive is global**: never `DOMContentLoaded`; the controller must clean up on `turbo:before-cache` so cached snapshots carry no visible tooltip.
- **No Bootstrap JS**: it is UMD and unloadable via importmap — do not import anything from `"bootstrap"`.
- **VCS is Mercurial (hg), not git.** Commit messages lead with WHY (first paragraph = motivation), and every `hg commit` names explicit files (the repo may have unrelated dirty changes — never commit bare `hg commit -m`).
- **SCSS builds**: after editing `application.scss`, run `bin/rails dartsass:build` (output `app/assets/builds/application.css` is not committed).
- **Tests are written AFTER implementation, on request**: project convention (CLAUDE.md Testing) overrides the default TDD flow — Task 3 ends by asking dae whether to write tests. Do not write tests unprompted.
- **UI approval rule**: dae approves styling changes only after seeing rendered headless-Firefox screenshots (Task 3).
- **Security**: tooltip text is set via `textContent`, never `innerHTML`.

---

### Task 1: Tooltip controller, `.app-tooltip` styles, layout wiring, staff-show conversion

**Files:**
- Create: `app/javascript/controllers/tooltip_controller.js`
- Modify: `app/assets/stylesheets/application.scss` (affordance rule ~line 288; new `.app-tooltip` block after it)
- Modify: `app/views/layouts/application.html.haml:28` (`%body`)
- Modify: `app/views/staffs/show.html.haml:137,144`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the `data-tooltip="<text>"` attribute contract — any element carrying it gets a styled tooltip on hover/focus after 100 ms; multi-line text uses literal `\n` (rendered via `white-space: pre-line`). Task 2 relies on this attribute name exactly. Also produces the CSS classes `.app-tooltip` (the floating div) and the affordance selector covering `td[data-tooltip]`/`th[data-tooltip]`.

- [ ] **Step 1: Create the controller**

Controllers are auto-registered from `app/javascript/controllers/` by `eagerLoadControllersFrom` (see `controllers/index.js`) — no registration edit needed. Create `app/javascript/controllers/tooltip_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Styled replacement for native title tooltips on informational hover text.
// Native titles have a fixed ~1s hover delay and a tiny unstylable OS font;
// Bootstrap Tooltip needs Bootstrap JS, which is unusable here (UMD, no
// exports — see CLAUDE.md Asset Pipeline). Attached once to <body>; event
// delegation picks up any [data-tooltip] element, including rows DataTables
// re-renders. The tooltip div is position:fixed so .table-responsive's
// overflow can't clip it (which is why this isn't a pure-CSS ::after).
const SHOW_DELAY_MS = 100
const GAP_PX = 6
const VIEWPORT_MARGIN_PX = 8

export default class extends Controller {
  connect() {
    this.tip = null
    this.trigger = null
    this.timer = null
    this.element.addEventListener("mouseover", this.show)
    this.element.addEventListener("mouseout", this.hide)
    this.element.addEventListener("focusin", this.show)
    this.element.addEventListener("focusout", this.hide)
    this.element.addEventListener("keydown", this.onKeydown)
    // capture — scroll events don't bubble out of .table-responsive, and a
    // fixed-position tooltip goes stale the moment anything scrolls
    window.addEventListener("scroll", this.hideNow, { capture: true, passive: true })
    document.addEventListener("turbo:before-cache", this.teardown)
  }

  disconnect() {
    this.teardown()
    this.element.removeEventListener("mouseover", this.show)
    this.element.removeEventListener("mouseout", this.hide)
    this.element.removeEventListener("focusin", this.show)
    this.element.removeEventListener("focusout", this.hide)
    this.element.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("scroll", this.hideNow, { capture: true })
    document.removeEventListener("turbo:before-cache", this.teardown)
  }

  show = (event) => {
    const trigger = event.target.closest?.("[data-tooltip]")
    if (!trigger || trigger === this.trigger) return
    this.hideNow()
    this.trigger = trigger
    this.timer = setTimeout(() => this.display(trigger), SHOW_DELAY_MS)
  }

  hide = (event) => {
    const trigger = event.target.closest?.("[data-tooltip]")
    if (!trigger || trigger !== this.trigger) return
    // moving between descendants of the same trigger is not a real leave
    if (event.relatedTarget && trigger.contains(event.relatedTarget)) return
    this.hideNow()
  }

  onKeydown = (event) => {
    if (event.key === "Escape") this.hideNow()
  }

  hideNow = () => {
    clearTimeout(this.timer)
    this.timer = null
    this.trigger = null
    if (this.tip) this.tip.style.display = "none"
  }

  // Removing (not just hiding) keeps Turbo's page snapshot free of the div,
  // so restored pages don't accumulate orphans across visits.
  teardown = () => {
    this.hideNow()
    this.tip?.remove()
    this.tip = null
  }

  display(trigger) {
    const text = trigger.dataset.tooltip
    if (!trigger.isConnected || !text) { this.hideNow(); return } // Turbo replaced it mid-delay
    const tip = this.tipElement()
    tip.textContent = text
    tip.style.display = "block"
    tip.style.visibility = "hidden" // measure first, place before revealing
    const r = trigger.getBoundingClientRect()
    const t = tip.getBoundingClientRect()
    let left = r.left + r.width / 2 - t.width / 2
    left = Math.max(VIEWPORT_MARGIN_PX, Math.min(left, window.innerWidth - t.width - VIEWPORT_MARGIN_PX))
    let top = r.top - t.height - GAP_PX
    if (top < VIEWPORT_MARGIN_PX) top = r.bottom + GAP_PX // flip below near viewport top
    tip.style.left = `${Math.round(left)}px`
    tip.style.top = `${Math.round(top)}px`
    tip.style.visibility = "visible"
  }

  tipElement() {
    if (!this.tip) {
      this.tip = document.createElement("div")
      this.tip.className = "app-tooltip"
      this.tip.setAttribute("role", "tooltip")
      document.body.appendChild(this.tip)
    }
    return this.tip
  }
}
```

- [ ] **Step 2: Add `.app-tooltip` styles and extend the affordance rule**

In `app/assets/stylesheets/application.scss`, find the existing block (~line 285):

```scss
// Report cells that carry a hover breakdown (column title_key:) — native
// title tooltips are invisible affordances, so mark the cell with a dotted
// underline + help cursor to make the hover discoverable.
.table > tbody > tr > td[title] {
  cursor: help;
  text-decoration: underline dotted;
  text-underline-offset: 3px;
}
```

Replace it with (the `td[title]` selector stays until Task 2 finishes converting the report partial, then gets dropped there):

```scss
// Cells that carry a hover breakdown (report column title_key:, teaching
// history) — tooltips are invisible affordances, so mark the cell with a
// dotted underline + help cursor to make the hover discoverable.
// td[title] is transitional and is removed when the last title: view
// converts to data-tooltip.
.table > tbody > tr > td[title],
.table > tbody > tr > td[data-tooltip],
.table > thead > tr > th[data-tooltip] {
  cursor: help;
  text-decoration: underline dotted;
  text-underline-offset: 3px;
}

// Styled tooltip (tooltip_controller.js) — replaces native title tooltips
// on informational hover text: native titles have a fixed ~1s hover delay
// and a tiny unstylable OS font, and Bootstrap Tooltip needs Bootstrap JS
// (UMD, unusable via importmap — see CLAUDE.md Asset Pipeline). The
// controller sets position:fixed coordinates so .table-responsive's
// overflow-x:auto cannot clip the tooltip on top rows.
.app-tooltip {
  position: fixed;
  display: none;
  max-width: 320px;
  padding: 0.375rem 0.625rem;
  background-color: $popover-bg;
  color: $body-color-dark;
  border: 1px solid lighten($dark, 18%);
  border-radius: 6px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
  font-size: 0.8125rem;    // the readability fix — native OS tooltips are smaller
  line-height: 1.4;
  white-space: pre-line;   // cohort breakdowns join lines with \n
  z-index: 1080;           // above the offcanvas sidebar (z-index 1050)
  pointer-events: none;    // never steal hover from the page
}
```

- [ ] **Step 3: Attach the controller to `<body>`**

In `app/views/layouts/application.html.haml` line 28, change:

```haml
  %body
```

to:

```haml
  %body{"data-controller" => "tooltip"}
```

(Only this layout — the auth layout has no tooltips.)

- [ ] **Step 4: Convert the two staff-show spots**

In `app/views/staffs/show.html.haml`, line 137:

```haml
                  = link_to c[:course_no], c[:course], title: c[:name]
```

becomes:

```haml
                  = link_to c[:course_no], c[:course], data: { tooltip: c[:name] }
```

Line 144:

```haml
                  %td.text-center{title: secs && "Section#{"s" if secs.size > 1} #{secs.join(", ")}"}= secs&.size
```

becomes:

```haml
                  %td.text-center{"data-tooltip" => secs && "Section#{"s" if secs.size > 1} #{secs.join(", ")}"}= secs&.size
```

(HAML omits inline attributes whose value is nil, so empty cells get no attribute — same behavior as `title:` had.)

- [ ] **Step 5: Build CSS and verify by hand**

```bash
bin/rails dartsass:build
```

Expected: exits 0, no Sass errors.

Start the server if not running: `AUTO_LOGIN=1 bin/rails server -p 3000` (background). Then:

```bash
curl -s http://localhost:3000/staffs/14 | grep -o 'data-tooltip="[^"]*"' | head -5
curl -s http://localhost:3000/staffs/14 | grep -c 'data-controller="tooltip"'
```

Expected: several `data-tooltip="Section..."` / course-name matches; body count `1`. There must be **no** remaining `title=` on the teaching-history table cells: `curl -s http://localhost:3000/staffs/14 | grep -c 'td[^>]*title='` → `0`.

- [ ] **Step 6: Commit**

```bash
hg commit \
  app/javascript/controllers/tooltip_controller.js \
  app/assets/stylesheets/application.scss \
  app/views/layouts/application.html.haml \
  app/views/staffs/show.html.haml \
  -m "Add styled data-tooltip controller; convert teaching history hover text

Native title tooltips take ~1s to appear (browser-fixed, unchangeable) and
render in a tiny unstylable OS font — dae flagged both on the teaching
history matrix and the data coverage report. Bootstrap Tooltip can't fix
this (Bootstrap JS is UMD, unloadable via importmap) and pure-CSS ::after
tooltips get clipped by .table-responsive's overflow on exactly these
tables, so a fixed-position div is required.

- tooltip_controller.js: dependency-free Stimulus controller on <body>,
  event delegation over [data-tooltip], single shared position:fixed div,
  100ms show delay, flip-below near viewport top, hides on scroll/Escape/
  turbo:before-cache, textContent only
- .app-tooltip theme styles (popover bg, 0.8125rem, pre-line) + dotted
  affordance extended to data-tooltip cells (td[title] kept transitionally)
- staffs/show teaching history converted to data-tooltip

Spec: docs/superpowers/specs/2026-07-16-styled-tooltip-design.md"
```

---

### Task 2: Convert report partial and grades-distribution header; drop the transitional `td[title]` affordance selector

**Files:**
- Modify: `app/views/reports/_result_table.html.haml:33-45`
- Modify: `app/views/grades/distribution.html.haml:61`
- Modify: `app/assets/stylesheets/application.scss` (affordance rule from Task 1 Step 2)

**Interfaces:**
- Consumes: the `data-tooltip` attribute contract from Task 1 (attribute name `data-tooltip`, `\n` for line breaks — `Reports::DataCoverage#cohort_breakdown` already emits `\n`-joined text and needs **no change**; the `title_key:` column-spec key also keeps its name).
- Produces: nothing further tasks depend on.

- [ ] **Step 1: Convert the report result partial**

In `app/views/reports/_result_table.html.haml`, the cell block currently reads (lines 33–45):

```haml
                -# Optional per-cell hooks, all declared on the column spec:
                -#   align:     CSS class for th+td (e.g. "text-end") — explicit
                -#              alignment so DataTables' type sniffing (which
                -#              left-aligns any column containing "—") can't
                -#              produce mixed-aligned columns
                -#   class_key: row key holding a flag class ("report-cell-missing")
                -#   title_key: row key holding hover text (native tooltip)
                -# CSV export ignores all of them (ReportExporter reads only col[:key]).
                -# The attr hash is .compact-ed because Haml renders nil dynamic
                -# attributes as empty strings (title="") — which would give EVERY
                -# cell the td[title] hover affordance, not just breakdown cells.
                - td_attrs = { class: [col[:align], (row[col[:class_key]] if col[:class_key])].compact.presence, title: (row[col[:title_key]] if col[:title_key]) }.compact
                %td{td_attrs}= row[col[:key]]
```

Replace the last comment lines and the `td_attrs` line so the block becomes:

```haml
                -# Optional per-cell hooks, all declared on the column spec:
                -#   align:     CSS class for th+td (e.g. "text-end") — explicit
                -#              alignment so DataTables' type sniffing (which
                -#              left-aligns any column containing "—") can't
                -#              produce mixed-aligned columns
                -#   class_key: row key holding a flag class ("report-cell-missing")
                -#   title_key: row key holding hover text (styled tooltip —
                -#              tooltip_controller.js; \n in the text renders
                -#              as line breaks via white-space: pre-line)
                -# CSV export ignores all of them (ReportExporter reads only col[:key]).
                -# The attr hash is .compact-ed because Haml renders nil dynamic
                -# attributes as empty strings (data-tooltip="") — which would give
                -# EVERY cell the hover affordance, not just breakdown cells.
                - td_attrs = { class: [col[:align], (row[col[:class_key]] if col[:class_key])].compact.presence, "data-tooltip": (row[col[:title_key]] if col[:title_key]) }.compact
                %td{td_attrs}= row[col[:key]]
```

- [ ] **Step 2: Convert the grades-distribution header**

In `app/views/grades/distribution.html.haml` line 61:

```haml
              %th.text-center{title: "Percent of A–F grades that are C or higher"} % ≥ C
```

becomes:

```haml
              %th.text-center{"data-tooltip" => "Percent of A–F grades that are C or higher"} % ≥ C
```

- [ ] **Step 3: Drop the transitional `td[title]` selector**

In `application.scss`, the affordance rule from Task 1 loses its first selector line and the transitional comment sentence, becoming exactly:

```scss
// Cells that carry a hover breakdown (report column title_key:, teaching
// history) — tooltips are invisible affordances, so mark the cell with a
// dotted underline + help cursor to make the hover discoverable.
.table > tbody > tr > td[data-tooltip],
.table > thead > tr > th[data-tooltip] {
  cursor: help;
  text-decoration: underline dotted;
  text-underline-offset: 3px;
}
```

- [ ] **Step 4: Build CSS and verify**

```bash
bin/rails dartsass:build
curl -s "http://localhost:3000/reports/data_coverage?run=1&commit=Run+report" | grep -o 'data-tooltip="[^"]*"' | head -3
curl -s "http://localhost:3000/grades/distribution" | grep -c 'data-tooltip="Percent'
```

Expected: cohort-breakdown matches like `data-tooltip="CP: 450` (the `\n` renders as a literal newline inside the attribute — the grep shows the first line); distribution count ≥ 1. Confirm no informational `title=` remains in either page's table markup and `grep -c 'td\[title\]' app/assets/stylesheets/application.scss` → `0`.

- [ ] **Step 5: Commit**

```bash
hg commit \
  app/views/reports/_result_table.html.haml \
  app/views/grades/distribution.html.haml \
  app/assets/stylesheets/application.scss \
  -m "Convert report title_key cells and distribution header to data-tooltip

Finishes the native-title replacement started with tooltip_controller.js:
the data coverage cohort breakdown and the '% >= C' explanation now use the
styled instant tooltip instead of the ~1s tiny native one. title_key: stays
the column-spec key — only the rendered attribute changed — and \n-joined
breakdown text still renders multi-line via white-space: pre-line.

Also drops the transitional td[title] affordance selector: no informational
title= hover text remains (icon action buttons keep native title on purpose
— the icon already conveys the action)."
```

---

### Task 3: Screenshot verification, backlog check, dae review gate

**Files:**
- Create: `<scratchpad>/tooltip_shots.rb` (scratchpad only — never committed)
- Read: `docs/backlog.md`

**Interfaces:**
- Consumes: converted pages from Tasks 1–2; running dev server (`AUTO_LOGIN=1 bin/rails server -p 3000`).
- Produces: screenshots for dae's approval; a tests-or-not decision from dae.

- [ ] **Step 1: Backlog trigger check**

CLAUDE.md requires opening `docs/backlog.md` whenever a report or entity show page changes — both happened here. Read it, check the triggered items (entity→report cross-links, report↔entity overlap review), and state explicitly in the summary to dae whether each applies or is consciously skipped (this change is a hover-attribute rename, so "skip" is the likely call — but say so out loud).

- [ ] **Step 2: Write the screenshot script**

Create `<scratchpad>/tooltip_shots.rb` (Selenium + headless Firefox, same stack as system tests; `selenium-webdriver` is in the bundle):

```ruby
# Screenshots of the styled tooltips for dae's UI review.
# Prereq: AUTO_LOGIN=1 bin/rails server -p 3000 (running)
# Run:    bundle exec ruby tooltip_shots.rb <output_dir>
require "selenium-webdriver"

out_dir = ARGV[0] || "."
options = Selenium::WebDriver::Firefox::Options.new
options.add_argument("-headless")
options.add_argument("--width=1400")
options.add_argument("--height=900")
driver = Selenium::WebDriver.for(:firefox, options: options)

def shoot(driver, url, hover_css, path)
  driver.navigate.to(url)
  sleep 2 # Turbo + DataTables settle
  el = driver.find_element(css: hover_css)
  driver.action.move_to(el).perform
  sleep 0.5 # > 100ms show delay
  raise "tooltip not visible on #{url}" unless driver.find_element(css: ".app-tooltip").displayed?
  driver.save_screenshot(path)
  puts "saved #{path}"
end

shoot(driver, "http://localhost:3000/staffs/14",
      ".teaching-history-table tbody td[data-tooltip]",
      File.join(out_dir, "teaching-history-tooltip.png"))
shoot(driver, "http://localhost:3000/staffs/14",
      ".teaching-history-table thead a[data-tooltip]",
      File.join(out_dir, "teaching-history-header-tooltip.png"))
shoot(driver, "http://localhost:3000/reports/data_coverage?run=1&commit=Run+report",
      "td[data-tooltip]",
      File.join(out_dir, "data-coverage-tooltip.png"))
driver.quit
```

- [ ] **Step 3: Run it and read the screenshots**

Run from the repo root so Bundler finds the Gemfile, passing the scratchpad as both script path and output dir:

```bash
cd /home/dae/cp-api && bundle exec ruby <scratchpad>/tooltip_shots.rb <scratchpad>
```

(`<scratchpad>` = the session scratchpad directory listed in your system prompt.)

Expected: three `saved ...png` lines, no "tooltip not visible" raise. Read all three PNGs (Read tool) and check: tooltip visible and unclipped (including on the TOP row of the data-coverage table — that's the clipping case that motivated fixed positioning), readable font size, theme-matching colors, multi-line cohort breakdown on separate lines.

- [ ] **Step 4: Present to dae and ask about tests**

Show dae the three screenshots plus the backlog-check outcome, and ask (a) styling approval / tweaks, and (b) whether to write tests now — candidate: a system test hovering a teaching-history cell and a data-coverage breakdown cell, asserting `.app-tooltip` becomes visible with expected multi-line text. Do not proceed to tests without dae's yes.
