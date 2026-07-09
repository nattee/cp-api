# Staff Teaching History Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Teaching History" card on the staff show page: a career-wide matrix with rows = semester (newest first), columns = courses (most-taught first, merged across curriculum revisions), cells = section numbers, capped to the last 20 years with a "Show all" escape hatch.

**Architecture:** One pivot method on `Staff` returning a value object (`TeachingHistory` Struct); `StaffsController#show` calls it; a new card in `staffs/show.html.haml` renders the matrix with 90°-rotated course-number column headers (CSS `writing-mode` + `rotate(180deg)`).

**Tech Stack:** Rails 8.1, HAML, Dart Sass (run `bin/rails dartsass:build` after SCSS edits), Minitest + fixtures.

**Spec:** `docs/superpowers/specs/2026-07-09-staff-teaching-history-design.md`

## Global Constraints

- **Mercurial, not git.** Commit with `hg add <files>` / `hg commit <explicit files> -m "..."` — always name the files (the repo often has unrelated dirty changes). Commit messages lead with WHY (first paragraph = motivation), then what.
- **Testing flow override:** this project does NOT use TDD. Per CLAUDE.md, after implementing a feature ask the user whether to write tests. Task 4 is therefore **gated**: ask first, only execute if the user says yes.
- **UI approval:** dae approves styling only after seeing rendered screenshots (headless Firefox). Task 3 shows the screenshot **before** the view/SCSS commit.
- Year fields are B.E. (`Semester#year_be`, `Course#revision_year_be`); UI labels that show years must say the era — the matrix shows terms as `2568/2` which is already unambiguous B.E.
- Intranet-only: no CDN links or external URLs.
- SCSS: our overrides/components live in `app/assets/stylesheets/application.scss`; new component blocks get a header comment explaining WHY.

---

### Task 1: `Staff#teaching_history` pivot method

**Files:**
- Modify: `app/models/staff.rb` (add Struct after the `ACADEMIC_TITLES` constant, method after `on_leave?`)

**Interfaces:**
- Consumes: existing associations `Staff has_many :teachings`, `Teaching belongs_to :section`, `Section belongs_to :course_offering`, `CourseOffering belongs_to :course, :semester`.
- Produces: `Staff#teaching_history(max_years: 20)` → `Staff::TeachingHistory` Struct with members `semesters` (`[Semester]` newest first), `courses` (`[{ course_no: String, name: String, course: Course }]` most-taught first), `cells` (`Hash{[semester_id, course_no] => String}` e.g. `"1, 33"`), `capped` (Boolean). Returns `nil` when the staff has no teachings. `max_years: nil` disables the cap. Tasks 2 and 4 rely on these exact names.

- [ ] **Step 1: Add the Struct and method to `app/models/staff.rb`**

After the `ACADEMIC_TITLES` constant (line 23), add:

```ruby
  # Value object returned by #teaching_history — the career-wide teaching
  # matrix rendered on the staff show page.
  TeachingHistory = Struct.new(:semesters, :courses, :cells, :capped, keyword_init: true)
```

After the `on_leave?` method, add:

```ruby
  # Pivot of every Teaching this staff member has, for the Teaching History
  # card: rows = semesters actually taught in (newest first), columns =
  # courses merged across curriculum revisions by course_no (most-taught
  # first), cells = section numbers. The max_years window is anchored at the
  # most recent teaching — not today — so a retired lecturer still shows
  # their last active years.
  #
  #   semesters — [Semester] newest first, only terms with at least one teaching
  #   courses   — [{ course_no:, name:, course: }] by terms-taught desc, then
  #               course_no; :course is the latest revision taught (for linking)
  #   cells     — { [semester_id, course_no] => "1, 33" }
  #   capped    — true when older semesters were cut off by max_years
  #
  # Returns nil when the staff has never taught. max_years: nil = no cap.
  def teaching_history(max_years: 20)
    all = teachings.includes(section: { course_offering: [ :course, :semester ] }).to_a
    return nil if all.empty?

    semesters_all = all.map { |t| t.section.course_offering.semester }
                       .uniq.sort_by { |s| [ -s.year_be, -s.semester_number ] }
    semesters = semesters_all
    if max_years
      min_year = semesters_all.first.year_be - (max_years - 1)
      semesters = semesters_all.select { |s| s.year_be >= min_year }
    end

    visible_ids = semesters.map(&:id).to_set
    visible = all.select { |t| visible_ids.include?(t.section.course_offering.semester_id) }

    courses = visible.group_by { |t| t.section.course_offering.course.course_no }
                     .map do |course_no, ts|
                       latest = ts.map { |t| t.section.course_offering.course }.max_by(&:revision_year_be)
                       terms  = ts.map { |t| t.section.course_offering.semester_id }.uniq.size
                       [ terms, { course_no: course_no, name: latest.name, course: latest } ]
                     end
                     .sort_by { |terms, c| [ -terms, c[:course_no] ] }
                     .map(&:last)

    cells = visible.group_by { |t| [ t.section.course_offering.semester_id,
                                     t.section.course_offering.course.course_no ] }
                   .transform_values { |ts| ts.map { |t| t.section.section_number }.uniq.sort.join(", ") }

    TeachingHistory.new(semesters: semesters, courses: courses, cells: cells,
                        capped: semesters.size < semesters_all.size)
  end
```

- [ ] **Step 2: Smoke-check in the console**

Run:
```bash
cd /home/dae/cp-api && bin/rails runner '
h = Staff.find(38).teaching_history
puts h ? "semesters=#{h.semesters.map(&:display_name)} courses=#{h.courses.map { |c| c[:course_no] }} capped=#{h.capped}" : "nil"
puts Staff.new.teaching_history.inspect'
```
Expected: first line lists real terms (e.g. `semesters=["2569/2", "2568/2", "2568/1"] courses=[...] capped=false`), second line `nil`. No exceptions.

- [ ] **Step 3: Commit**

```bash
cd /home/dae/cp-api && hg commit app/models/staff.rb -m "Add Staff#teaching_history career-matrix pivot

The staff page and the staff_courses_by_year report each show one term
or one year of teaching; nothing shows a lecturer's whole career at a
glance. This pivot powers a Teaching History matrix card: rows are
semesters actually taught (newest first, capped to the last 20 active
years), columns are courses merged across curriculum revisions by
course_no (most-taught first), cells are section numbers.

- Staff::TeachingHistory Struct (semesters/courses/cells/capped)
- window anchored at the most recent teaching, not today, so retired
  lecturers keep their last active years visible"
```

---

### Task 2: Controller param + Teaching History card + rotated-header SCSS

**Files:**
- Modify: `app/controllers/staffs_controller.rb` (top of `show`, line 10)
- Modify: `app/views/staffs/show.html.haml` (append card at end of file, after the per-semester Teaching card)
- Modify: `app/assets/stylesheets/application.scss` (new component block after the `.wl-cell-link:hover` rule, ~line 157)

**Interfaces:**
- Consumes: `Staff#teaching_history(max_years:)` from Task 1 (exact Struct members `semesters`, `courses`, `cells`, `capped`; `courses` entries are hashes with `:course_no`, `:name`, `:course`).
- Produces: `@teaching_history` ivar; `?history=all` query param lifts the cap; CSS classes `.teaching-history-table` and `.th-rotated` (Task 3 screenshots this card).

**NOTE: do not commit in this task** — the visual result needs user approval first (Task 3).

- [ ] **Step 1: Set `@teaching_history` in `StaffsController#show`**

In `app/controllers/staffs_controller.rb`, at the top of `show` (before the `@teaching_semesters` query), add:

```ruby
  def show
    @teaching_history = @staff.teaching_history(max_years: params[:history] == "all" ? nil : 20)

```
(existing body of `show` continues unchanged.)

- [ ] **Step 2: Append the card to `app/views/staffs/show.html.haml`**

At the end of the file (after the `- if @teaching_semesters.any?` card), add:

```haml
- if @teaching_history
  .card.mt-3
    .card-body.p-3
      %h5.card-title.fw-semibold.d-flex.align-items-center.mb-3
        %span.material-symbols.resource-icon.me-2 history_edu
        Teaching History
      .table-responsive
        %table.table.table-hover.mb-0.teaching-history-table
          %thead
            %tr
              %th Term
              - @teaching_history.courses.each do |c|
                %th.th-rotated
                  = link_to c[:course_no], c[:course], title: c[:name]
          %tbody
            - @teaching_history.semesters.each do |sem|
              %tr
                %th{scope: "row"}= sem.display_name
                - @teaching_history.courses.each do |c|
                  %td.text-center= @teaching_history.cells[[ sem.id, c[:course_no] ]]
      - if @teaching_history.capped
        %p.text-muted.small.mt-2.mb-0
          Showing the last 20 years —
          = link_to "Show all", staff_path(@staff, history: "all")
```

- [ ] **Step 3: Add the rotated-header component block to `application.scss`**

After the `.wl-cell-link:hover` rule (~line 157), add:

```scss
// Teaching History matrix (staff show page). One column per course the staff
// member has ever taught — easily 20+ over a career — so horizontal course-no
// headers would blow out the card width. Rotate them vertical instead,
// reading bottom-to-top and ending at the data row, which shrinks each
// column to roughly one line-height.
.teaching-history-table thead th { vertical-align: bottom; }  // "Term" label sits on the same baseline as rotated headers
.teaching-history-table th.th-rotated {
  writing-mode: vertical-rl;   // vertical text (inline axis runs top→bottom)
  transform: rotate(180deg);   // flip to read bottom→top
  line-height: 1.2;            // column width ≈ one line of the 0.7rem header type
}
// Header links go to the course page but must keep the quiet-label header
// look — link blue on 20+ headers would out-shout the data (same idea as
// .wl-cell-link). Hover restores the underline affordance.
.teaching-history-table th.th-rotated a { color: inherit; text-decoration: none; }
.teaching-history-table th.th-rotated a:hover { text-decoration: underline; }
```

- [ ] **Step 4: Rebuild CSS**

Run: `cd /home/dae/cp-api && bin/rails dartsass:build`
Expected: exits 0, `app/assets/builds/application.css` regenerated (no Sass errors).

---

### Task 3: Visual verification + user approval + commit

**Files:**
- None modified — screenshot to `/tmp/claude-1002/-home-dae-cp-api/d8833ada-a7d3-4c6d-8115-84ffa5f3f6ec/scratchpad/teaching-history.png`

**Interfaces:**
- Consumes: the card from Task 2 rendered at `/staffs/38`.
- Produces: user approval; then the Task 2 commit.

- [ ] **Step 1: Start a dev server on a spare port and screenshot**

```bash
cd /home/dae/cp-api && AUTO_LOGIN=1 bin/rails server -p 3111 -d --pid tmp/pids/server-3111.pid
sleep 3
firefox --headless --window-size=1400,1400 \
  --screenshot /tmp/claude-1002/-home-dae-cp-api/d8833ada-a7d3-4c6d-8115-84ffa5f3f6ec/scratchpad/teaching-history.png \
  "http://localhost:3111/staffs/38"
kill "$(cat /home/dae/cp-api/tmp/pids/server-3111.pid)"
```
Expected: PNG written. (Port 3111 avoids colliding with a running `bin/dev` on 3000.)

- [ ] **Step 2: Read the PNG and show it to the user**

Read the screenshot; confirm visually: rotated course-no headers reading bottom-to-top, terms newest-first, section numbers in cells, blank cells otherwise. Then present it to the user for approval (per dae's standing preference: styling ships only after a rendered screenshot). Iterate on SCSS if requested (re-run Task 2 Step 4 + this task's Step 1 after each change).

- [ ] **Step 3: After approval, commit Task 2's files**

```bash
cd /home/dae/cp-api && hg commit \
  app/controllers/staffs_controller.rb \
  app/views/staffs/show.html.haml \
  app/assets/stylesheets/application.scss \
  app/assets/builds/application.css \
  -m "Teaching History matrix card on the staff page

The per-semester Teaching card answers one term at a time; seeing a
lecturer's whole career meant clicking through the semester dropdown or
running the by-year report repeatedly. This card shows every term at a
glance: rows = semester newest first, columns = courses most-taught
first (merged across curriculum revisions), cells = section numbers.

- StaffsController#show exposes @teaching_history; ?history=all lifts
  the default 20-year cap (window anchored at last teaching)
- course-no column headers rotate 90° (writing-mode + rotate(180deg))
  so a career's worth of columns fits the card; headers link to the
  course page with the course name as tooltip"
```

(If `app/assets/builds/application.css` is not tracked in this repo — check with `hg status app/assets/builds/` before committing — drop it from the file list.)

---

### Task 4 (GATED — ask the user first): model tests for the pivot

Per CLAUDE.md: **ask the user whether to write tests now**, and briefly confirm the test list below before writing. Skip this task entirely if the user defers.

**Files:**
- Create: `test/models/staff_test.rb` (does not exist yet)

**Interfaces:**
- Consumes: `Staff#teaching_history` (Task 1); fixtures `staffs(:lecturer_smith)` (teaches sections 1+2 of course 2110101 in 2568/1), `courses(:intro_computing)` (`2110101`, revision 2565), `courses(:senior_project)` (`2110499`), `semesters(:sem_2568_1)`.
- Produces: regression coverage for row/column ordering, revision merge, cap anchoring.

- [ ] **Step 1: Write `test/models/staff_test.rb`**

```ruby
require "test_helper"

class StaffTest < ActiveSupport::TestCase
  # Builds the CourseOffering→Section→Teaching chain for one taught section.
  def teach(staff, course, year_be:, semester_number: 1, section_number: 1)
    semester = Semester.find_or_create_by!(year_be: year_be, semester_number: semester_number)
    offering = CourseOffering.where(course: course, semester: semester)
                             .first_or_create!(status: "confirmed")
    section  = Section.find_or_create_by!(course_offering: offering, section_number: section_number)
    Teaching.create!(staff: staff, section: section, load_ratio: 1.0)
  end

  test "teaching_history returns nil for staff who never taught" do
    staff = Staff.create!(title: "นาย", first_name: "New", last_name: "Hire",
                          staff_type: "lecturer", status: "active")
    assert_nil staff.teaching_history
  end

  test "teaching_history rows are taught semesters newest first with merged section cells" do
    staff = staffs(:lecturer_smith) # fixtures: sections 1 and 2 of 2110101 in 2568/1
    teach(staff, courses(:intro_computing), year_be: 2569, semester_number: 2)

    h = staff.teaching_history
    assert_equal [ "2569/2", "2568/1" ], h.semesters.map(&:display_name)
    assert_equal "1, 2", h.cells[[ semesters(:sem_2568_1).id, "2110101" ]]
    assert_not h.capped
  end

  test "teaching_history orders courses by terms taught, then course_no" do
    staff = staffs(:lecturer_smith)                      # 2110101: one term (2568/1)
    teach(staff, courses(:senior_project), year_be: 2569, semester_number: 1)
    teach(staff, courses(:senior_project), year_be: 2569, semester_number: 2)

    h = staff.teaching_history                           # 2110499: two terms → first
    assert_equal [ "2110499", "2110101" ], h.courses.map { |c| c[:course_no] }
  end

  test "teaching_history merges curriculum revisions under one column linking the latest" do
    staff = staffs(:lecturer_smith)                      # taught 2110101 rev 2565 in 2568/1
    new_rev = Course.create!(name: "Intro to Computing (rev)", course_no: "2110101",
                             revision_year_be: 2570, auto_generated: "none")
    teach(staff, new_rev, year_be: 2570)

    h = staff.teaching_history
    assert_equal [ "2110101" ], h.courses.map { |c| c[:course_no] }
    assert_equal new_rev, h.courses.first[:course]
    assert_equal "Intro to Computing (rev)", h.courses.first[:name]
  end

  test "teaching_history caps at max_years anchored at the most recent teaching" do
    staff = Staff.create!(title: "นาย", first_name: "Old", last_name: "Timer",
                          staff_type: "lecturer", status: "retired")
    teach(staff, courses(:intro_computing), year_be: 2540)
    teach(staff, courses(:intro_computing), year_be: 2521) # boundary: 2540-19, still in
    teach(staff, courses(:intro_computing), year_be: 2520) # one year past the window

    h = staff.teaching_history
    assert_equal [ 2540, 2521 ], h.semesters.map(&:year_be)
    assert h.capped

    full = staff.teaching_history(max_years: nil)
    assert_equal [ 2540, 2521, 2520 ], full.semesters.map(&:year_be)
    assert_not full.capped
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `cd /home/dae/cp-api && bin/rails test test/models/staff_test.rb`
Expected: `5 runs, 12 assertions, 0 failures, 0 errors`.

- [ ] **Step 3: Commit**

```bash
cd /home/dae/cp-api && hg add test/models/staff_test.rb && hg commit test/models/staff_test.rb -m "Test Staff#teaching_history pivot

The teaching-history matrix has ordering and windowing rules that are
easy to silently break (newest-first rows, most-taught-first columns,
revision merge by course_no, 20-year cap anchored at the last teaching
rather than today). Pin them down at the model level.

- new test/models/staff_test.rb covering nil-when-never-taught, row and
  column ordering, section-cell merging, revision merge, cap boundary"
```
