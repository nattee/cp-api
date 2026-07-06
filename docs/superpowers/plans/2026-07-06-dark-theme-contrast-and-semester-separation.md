# Dark Theme Contrast + Course History Semester Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make semester/group boundaries unmissable in the student Course History and lift cards off the near-black page canvas, per the approved spec `docs/superpowers/specs/2026-07-06-dark-theme-contrast-and-semester-separation-design.md`.

**Architecture:** Pure presentation change: two Sass variable values + one hardcoded JS color (Task 1), one SCSS rule block + spacer rows in one HAML view (Task 2), documentation of the deviations (Task 3). No models, controllers, routes, or migrations.

**Tech Stack:** Rails 8.1, HAML, Dart Sass (`bin/rails dartsass:build`), Bootstrap 5.3 (dark mode), Mercurial.

## Global Constraints

- **Version control is Mercurial (hg), not git.** Always commit with explicit file paths (the repo may have unrelated dirty files). Commit messages MUST lead with WHY (first paragraph = problem/motivation), then what changed.
- **No new tests in this plan.** This is a visual-only change; the project convention is to ask the user about tests after the feature is done. Existing suites must still pass.
- **After any SCSS edit, run `bin/rails dartsass:build`** — nothing recompiles automatically unless `bin/dev` (watch mode) is running.
- **SCSS comments:** every non-obvious value gets a comment stating what it was before and why it changed (project convention).
- **Do NOT set `$card-border-color`.** Bootstrap dark mode already draws `rgba(255,255,255,0.15)` card borders; a custom `rgba(white,0.08)` border was mocked up and measured *dimmer* than the default (edge brightness 44 vs 60). This mistake is recorded in the spec — don't reintroduce it.
- **Visual verification** uses the script in Task 1 Step 3. It needs the dev server on `localhost:3000`. Check with `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/login` (expect `200` or `302`). If nothing is listening, start one: `bin/rails server -d` (daemonized; stop later with `kill $(cat tmp/pids/server.pid)`).

---

### Task 1: Opaque cards + softened body text (surface contrast)

**Files:**
- Modify: `app/assets/stylesheets/application.scss:26` (`$body-color-dark`)
- Modify: `app/assets/stylesheets/application.scss:32` (`$card-bg`)
- Modify: `app/javascript/controllers/chart_controller.js:40` (`TICK_COLOR`)
- Create: `tmp/visual_check.rb` (throwaway verification script, not committed)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks depend on programmatically. Task 3 documents these values (`#101828` opaque, `#e6edf3`).

- [ ] **Step 1: Change the two Sass variables**

In `app/assets/stylesheets/application.scss`, replace:

```scss
// Font color (Bootstrap dark mode text)
$body-color-dark: #ffffff;                   // pure white — oklch(1 0 0)
```

with:

```scss
// Font color (Bootstrap dark mode text)
// Softened from palette's pure #ffffff (oklch(1 0 0)): max contrast on every
// word is glarey over long sessions and leaves no headroom for emphasis.
// #e6edf3 is GitHub dark's body text. Deliberate deviation from --foreground.
$body-color-dark: #e6edf3;
```

and replace:

```scss
$card-bg:              rgba(#101828, 0.6);            // card — oklch(0.21 0.034 264.665 / 0.6), semi-transparent
```

with:

```scss
$card-bg:              #101828;                       // card — oklch(0.21 0.034 264.665), alpha DROPPED: at /0.6 over $dark the card composited to rgb(11,16,31), ~13 RGB pts above the canvas — all surfaces melted together (2026-07-06 spec)
```

- [ ] **Step 2: Mirror the text color in chart ticks**

`docs/shadcn-color-mapping.md` documents `TICK_COLOR` as "Same as `$body-color-dark`". In `app/javascript/controllers/chart_controller.js`, replace:

```js
const TICK_COLOR = "#ffffff"
```

with:

```js
const TICK_COLOR = "#e6edf3" // tracks $body-color-dark (see docs/shadcn-color-mapping.md)
```

- [ ] **Step 3: Create the visual verification script**

Write `tmp/visual_check.rb` (tmp/ is not tracked; do not commit):

```ruby
# Screenshots /students/3040 (both Course History tabs) for visual verification.
# Usage: bundle exec ruby tmp/visual_check.rb
# Needs the dev server on localhost:3000; works with or without AUTO_LOGIN.
require "selenium-webdriver"

options = Selenium::WebDriver::Firefox::Options.new
options.add_argument("--headless")
options.add_argument("--width=1600")
options.add_argument("--height=1400")

driver = Selenium::WebDriver.for(:firefox, options: options)
driver.get("http://localhost:3000/login")
if driver.current_url.include?("/login")
  driver.find_element(css: "input[name='username'], input#username").send_keys("root")
  driver.find_element(css: "input[type='password']").send_keys("password123")
  driver.find_element(css: "input[type='submit'], button[type='submit']").click
  sleep 1
end

driver.get("http://localhost:3000/students/3040")
sleep 2
driver.save_screenshot("tmp/check_by_course_group.png")

driver.find_elements(css: "[data-tabs-target='tab']")[1].click
sleep 0.5
driver.execute_script("window.scrollTo(0, 600);")
sleep 0.3
driver.save_screenshot("tmp/check_by_semester.png")
puts "saved tmp/check_by_course_group.png and tmp/check_by_semester.png"
driver.quit
```

- [ ] **Step 4: Build CSS and verify visually**

```bash
bin/rails dartsass:build
bundle exec ruby tmp/visual_check.rb
```

Read `tmp/check_by_course_group.png` and confirm: cards are visibly lighter than the page/sidebar canvas with a clear 1px edge (the default Bootstrap border — unchanged); body text is still crisp (the white→#e6edf3 softening is intentionally subtle; anything obviously gray/dim is wrong).

- [ ] **Step 5: Run the unit test suite**

```bash
bin/rails test
```

Expected: PASS (no behavioral change; failures here mean something unrelated is broken — stop and report).

- [ ] **Step 6: Commit (hg, explicit files)**

```bash
hg commit app/assets/stylesheets/application.scss app/javascript/controllers/chart_controller.js -m "Make cards opaque and soften body text for surface contrast

Cards used rgba(#101828, 0.6), compositing to within ~13 RGB points of
the near-black page canvas — cards, page, and sidebar read as one flat
surface. Body text was pure #ffffff: maximum contrast on every word,
glarey over long sessions, with no headroom left for emphasis.

Card background becomes opaque #101828 (the existing Bootstrap default
border already provides the edge — deliberately NOT overridden, see
spec). Body text softens to #e6edf3, mirrored in chart_controller.js
TICK_COLOR which is documented as tracking \$body-color-dark.
Spec: docs/superpowers/specs/2026-07-06-dark-theme-contrast-and-semester-separation-design.md"
```

Note: `app/assets/builds/` is hg-ignored (compiled output) — nothing else to add.

---

### Task 2: Course History semester separation (gaps + accent band headers)

**Files:**
- Modify: `app/assets/stylesheets/application.scss:96-109` (`.table-group-header` block)
- Modify: `app/views/students/show.html.haml:195` (By Course Group tab loop)
- Modify: `app/views/students/show.html.haml:227` (By Semester tab loop)

**Interfaces:**
- Consumes: `$primary` (`#74d4ff`), `$light` (`#b8e6fe`), `$table-head-border-color` — all defined earlier in `application.scss`.
- Produces: CSS classes `.table-group-header` (restyled) and `.table-group-spacer` (new) — the HAML in this same task emits them; Task 3 documents the pattern.

- [ ] **Step 1: Restyle group headers and add spacer CSS**

In `app/assets/stylesheets/application.scss`, replace this block:

```scss
// Group header rows within a single table — used to separate sections (e.g. course
// groups, semesters) while keeping all columns aligned. Styled as a subtle label row
// with a stronger top border to visually separate groups.
.table-group-header td {
  background-color: rgba(white, 0.03);
  border-top: 1px solid $table-head-border-color;
  padding-top: 0.6rem;
  padding-bottom: 0.4rem;
  font-size: 0.85rem;
}
// First group header should not have a top border (thead border is enough)
.card .table > tbody > tr.table-group-header:first-child td {
  border-top: 0;
}
```

with:

```scss
// Group header rows within a single table — used to separate sections (e.g. course
// groups, semesters) while keeping all columns aligned. Styled as an accent band:
// visible tint, cyan bar on the left edge, label in $light and LARGER than the data
// rows. The old 3% tint at 0.85rem made headers recede below the data they label —
// 15+ semester groups blurred into one stream (2026-07-06 spec).
.table-group-header td {
  background-color: rgba(white, 0.05);          // was 0.03 — now a visible band
  border-top: 1px solid $table-head-border-color;
  box-shadow: inset 3px 0 0 $primary;           // accent bar; inset shadow, not border, so column widths don't shift
  padding-top: 0.65rem;
  padding-bottom: 0.5rem;
  font-size: 0.95rem;                           // was 0.85rem — header now outranks data rows
}
.table-group-header strong { color: $light; letter-spacing: 0.02em; }
// First group header should not have a top border (thead border is enough)
.card .table > tbody > tr.table-group-header:first-child td {
  border-top: 0;
}
// Spacer rows: a gap of card background between groups, so each group reads as its
// own block. Views emit one before each group header except the first.
.table-group-spacer td {
  padding: 0.7rem 0;
  border: 0;
  background: transparent;
}
// Suppress .table-hover highlight on spacers — an empty row must not light up.
// Must match Bootstrap's `.table-hover > tbody > tr:hover > *` specificity;
// a bare `.table-group-spacer td { box-shadow: none }` loses that fight.
.table-hover > tbody > tr.table-group-spacer:hover > td { box-shadow: none; }
```

- [ ] **Step 2: Emit spacer rows in the By Course Group tab**

In `app/views/students/show.html.haml` (~line 195), replace:

```haml
            %tbody
              - grouped.each do |group_name, group_grades|
                - group_credits = group_grades.select { |g| g.grade_weight }.sum { |g| g.course.credits.to_i }
                %tr.table-group-header
```

with:

```haml
            %tbody
              - grouped.each_with_index do |(group_name, group_grades), group_idx|
                - group_credits = group_grades.select { |g| g.grade_weight }.sum { |g| g.course.credits.to_i }
                - if group_idx.positive?
                  %tr.table-group-spacer
                    %td{colspan: 6}
                %tr.table-group-header
```

(Indentation: `- if group_idx.positive?` aligns with the `- group_credits` line; the `%tr` nests one level deeper, `%td` one deeper again. HAML is whitespace-sensitive.)

- [ ] **Step 3: Emit spacer rows in the By Semester tab**

In the same file (~line 227), replace:

```haml
            %tbody
              - by_term.each do |term_label, term_grades|
                - term_graded = term_grades.select { |g| g.grade_weight }
```

with:

```haml
            %tbody
              - by_term.each_with_index do |(term_label, term_grades), term_idx|
                - if term_idx.positive?
                  %tr.table-group-spacer
                    %td{colspan: 6}
                - term_graded = term_grades.select { |g| g.grade_weight }
```

- [ ] **Step 4: Build CSS and verify both tabs visually**

```bash
bin/rails dartsass:build
bundle exec ruby tmp/visual_check.rb
```

Read both PNGs and confirm, in each tab: (a) a clear gap of card background before every group header except the first; (b) header bands with a cyan bar on the left edge and light-blue bold labels larger than data rows; (c) columns still aligned across groups (still one table); (d) no stray border floating in the gaps.

- [ ] **Step 5: Run both test suites**

```bash
bin/rails test && bin/rails test:system
```

Expected: PASS. If a system test asserts on Course History table rows and fails on the new spacer rows, report it — do not silently rewrite test expectations.

- [ ] **Step 6: Commit (hg, explicit files)**

```bash
hg commit app/assets/stylesheets/application.scss app/views/students/show.html.haml -m "Separate course history semesters with gaps and accent band headers

Group header rows used a 3% white tint with text smaller than the data
rows, so the 15+ semester groups on a student page blurred into one
stream — boundaries were invisible while scanning.

Headers become accent bands (5% white tint, cyan inset bar, \$light
label at 0.95rem) and both Course History tabs emit a .table-group-spacer
row before each group except the first, creating a gap of card
background between blocks while keeping columns aligned in one table.
Hover highlight is suppressed on spacers at .table-hover specificity.
Spec: docs/superpowers/specs/2026-07-06-dark-theme-contrast-and-semester-separation-design.md"
```

(`app/assets/builds/` is hg-ignored — nothing else to add.)

---

### Task 3: Document the deviations and the spacer pattern

**Files:**
- Modify: `docs/shadcn-color-mapping.md:11` and `:24-25`
- Modify: `CLAUDE.md:94`

**Interfaces:**
- Consumes: the final values from Tasks 1-2 (`$card-bg: #101828` opaque, `$body-color-dark: #e6edf3`, `.table-group-spacer`).
- Produces: nothing — docs only.

- [ ] **Step 1: Update the palette-update instructions in the mapping doc**

In `docs/shadcn-color-mapping.md`, replace:

```markdown
   - **`$card-bg`**: if `--card` has an alpha (e.g. `/ 0.6`), use `rgba(<hex>, 0.6)`. If no alpha, use the hex directly.
```

with:

```markdown
   - **`$card-bg`**: always use the opaque hex from `--card` and **drop any alpha** (e.g. `/ 0.6`). Deliberate deviation: translucent cards composite to within ~13 RGB points of the canvas and all surfaces melt together (see 2026-07-06 contrast spec). Do not override `$card-border-color` either — the dark-mode default rgba(255,255,255,0.15) border is stronger than the rgba(white,0.08) that was once proposed and measured dimmer.
```

- [ ] **Step 2: Update the variable mapping table rows**

In the same file, replace:

```markdown
| `--foreground` | `$body-color-dark` | Body text color |
| `--card` | `$card-bg` | Card surfaces. Extract alpha if present (e.g. `/ 0.6` → `rgba(hex, 0.6)`) |
```

with:

```markdown
| `--foreground` | `$body-color-dark` | Body text color. **Deviation:** softened to `#e6edf3` (not the palette's pure `#ffffff`) to cut glare; keep the softening when updating. Also mirrored in `chart_controller.js` `TICK_COLOR`. |
| `--card` | `$card-bg` | Card surfaces. **Drop any alpha** — always opaque (see step 3 note above) |
```

- [ ] **Step 3: Update the CLAUDE.md group-header convention**

In `CLAUDE.md`, replace:

```markdown
- **Table group headers**: Use `.table-group-header` on `%tr` rows with a `%td{colspan: N}` to visually separate groups (e.g. course groups, semesters) within a **single** table. This keeps columns aligned across groups — do NOT use separate tables per group. Styled with subtle background and stronger top border.
```

with:

```markdown
- **Table group headers**: Use `.table-group-header` on `%tr` rows with a `%td{colspan: N}` to visually separate groups (e.g. course groups, semesters) within a **single** table. This keeps columns aligned across groups — do NOT use separate tables per group. Styled as an accent band (tint, cyan inset bar, `$light` label). Additionally emit a `%tr.table-group-spacer` with an empty `%td{colspan: N}` before each group header **except the first** — it renders as a gap that separates the groups into blocks. See the Course History tables in `app/views/students/show.html.haml` for the canonical usage.
```

- [ ] **Step 4: Commit (hg, explicit files)**

```bash
hg commit docs/shadcn-color-mapping.md CLAUDE.md -m "Document opaque-card and softened-text deviations plus spacer pattern

The shadcn mapping doc still instructed extracting --card's alpha and
mapping --foreground verbatim; after the 2026-07-06 contrast fixes both
are deliberate deviations, and a future palette update following the old
instructions would silently regress them. CLAUDE.md's group-header
convention predated the spacer-row pattern, so new group tables would
have been built without the gaps."
```

---

## Final Verification (after all tasks)

- `hg log -l 3` shows the three commits with why-first messages.
- `bundle exec ruby tmp/visual_check.rb` and eyeball both PNGs one last time against the spec's Decisions table.
- Spot-check `/dev/styleguide` (development only): card/table samples in the Color Playground should reflect the opaque card background (spec's verification section).
- Ask the user whether they want tests for the spacer-row rendering (project convention: ask after the feature is done — do not write them unprompted).
- Delete `tmp/visual_check.rb` and `tmp/check_*.png` (throwaway).
