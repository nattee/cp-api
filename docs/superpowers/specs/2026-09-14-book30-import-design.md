# 30-Year Book Alumni Import: Design

**Status:** approved by dae 2026-09-14 ("proceed with the import of the book as planned"). Companion
documents: `docs/book30-import-report.md` (matching results and outcome vocabulary, the
pre-import dry run), `docs/data-provenance-report.md` (where every existing row came from).
Prior analysis scripts live in `tmp/book30_report/scripts/` and are superseded by the code this
spec describes.

## Goal

Turn the alumni directory printed in the department's 30th-anniversary book (`book ครบรอบ 30 ปี.pdf`,
PDF pages 232–303, 4,010 printed lines under `รุ่น <CODE><NN>` headers) into database facts:

1. every printed line gets exactly one **log row** recording what was decided about it;
2. lines that match an existing student are **linked** to that student without changing it;
3. lines with no existing student become **students recorded from the book** (about 1,472);
4. the results are readable by admins inside the app, alongside a page describing where all
   other data came from.

## Decisions already taken (do not reopen)

| Question | Decision |
|---|---|
| Cohort with book data, no DB students | Believe the book: create every name. |
| Near match (a few characters, name change, neighbouring year) | Believe the DB: link, never edit DB names or years, log the book's variant. No human review. |
| Odd cases (double listings, two book names on one DB student, namesakes) | Apply the mechanical rule below, log it so it can be amended later. |
| CE cohorts | Deserve a programme group: `CE`, degree level `certificate`, first intake 2512. |
| Student ID for rows recorded from the book | Synthetic, non-numeric, deterministic from book position: `B30-<COHORT>-<NNN>` (e.g. `B30-CE01-001`). |
| English name columns | Made nullable; never transliterated or copied from Thai. |
| Programme revision for early cohorts | Latest revision started at or before the admission year; if none, the group's earliest revision (CP01–02 → `0018`, CS01–10 → `1027`). Ties (SE `0772`/`0773`, CD `0458`/`0459`) → the twin with more students admitted that year, else the lower code. Recorded in the remark. |
| Status | `unknown` (the book says "ever studied"). |
| Study track | `special` for CT cohorts; `regular` for CS cohorts from 2533 on; nil otherwise. |
| Sex | From the title: นาย → male; นาง, นางสาว, น.ส., นส., ว่าที่ ร.ต.หญิง → female; else nil. |
| Provenance mark | New `students.source` column; book rows carry `book30`. |
| CM01–CM04 | The 19 students with `C`-prefixed IDs filed under CP `0018` at 2535–2538 are re-filed to CM `0037` before matching. |
| Logging | One `book30_entries` row per printed line. DB students not in the book are computed live, not stored. |

## Inputs

- The PDF, at `/home/dae/book ครบรอบ 30 ปี.pdf` on dae's machine (`PDF=` overrides). Requires
  `mutool` (mupdf-tools). The directory pages and the parsing pipeline (PUA glyph decode, mark
  reordering, two-column split at x≈180, `รุ่น` headers, title stripping) already exist in
  `Book30Reconciler`; they move into `Book30::Directory` unchanged in behaviour.
- The book's own legend (PDF p. 231) fixes the epochs: CE 2512, CS 2514, CP 2517, CT 2533,
  CM 2535, CD 2541, SE 2545. Cohort NN enrolled in `epoch + NN − 1`. CT maps to the CS
  programme group. AJ/AS (faculty/staff) sections are skipped.

## Data model

### `students`

- `first_name`, `last_name` → nullable (`change_column_null`). Validation becomes
  `presence: true, unless: :legacy_source?` where `legacy_source?` is `source.in?(LEGACY_SOURCES)`.
- New `source` string NOT NULL default `"imported"`. `Student::SOURCES = %w[imported chulabooster
  manual book30]`, `Student::LEGACY_SOURCES = %w[book30]`, `Student::SOURCE_ICONS`. Migration
  backfill: rows created on 2026-07-05 (the ChulaBooster sync day; equivalently `remark LIKE
  'ChulaBooster sync%'` or `cb_status_code` set on a row created that day) → `chulabooster`;
  everything else → `imported`. `Chulabooster::StudentSync` sets `source: "chulabooster"` on
  create; `StudentsController#create` sets `source: "manual"`; importers leave the default.
- No other student column changes. Linked students are never modified by the import.

### `book30_entries` (new)

| column | type | notes |
|---|---|---|
| `cohort` | string, not null | e.g. `CP14` |
| `year_be` | integer, not null | from the epoch rule |
| `line_no` | integer, not null | 1-based position within the cohort, in reading order |
| `raw_line` | string, not null | as printed, after PUA decode and mark reordering |
| `first_name_th`, `last_name_th` | string, nullable | parsed; nil when unparsed |
| `alias_name` | string, nullable | text found in brackets (maiden name), also a following bracket-only line |
| `sex` | string, nullable | derived from the title |
| `outcome` | string, not null | one of `Book30Entry::OUTCOMES` (below) |
| `student_id` | bigint FK → students, nullable | the linked or created student |
| `note` | text | machine-written explanation, `; `-joined |
| timestamps | | |

Unique index on `(cohort, line_no)`. `belongs_to :student, optional: true`. `Student has_many
:book30_entries`.

`Book30Entry::OUTCOMES = %w[linked_exact linked_variant linked_other_year second_listing
duplicate_line create_book_only_cohort create_missing create_lost_claim create_namesake unparsed]`
with `LINK_OUTCOMES`, `CREATE_OUTCOMES`, `IGNORE_OUTCOMES` groupings.

### Programme group `CE` and programme `CE2512`

Seeded in `db/seeds/programs.rb` (idempotent). Group: code `CE`, `name_en` "Computer Science
Certificate", `name_th` "ประกาศนียบัตรคอมพิวเตอร์ไซแอนส์", `degree_level` `certificate`,
`degree_name` "Certificate in Computer Science", `degree_name_th` "ประกาศนียบัตร",
`degree_abbr` "Cert.", `field_of_study` "Computer Science", `first_intake_year_be` 2512.
Programme: `program_code` `CE2512` (synthetic, non-numeric on purpose: it can never collide with a
registrar code and is visibly not one), `year_started_be` 2512, `short_name` "CE", `active` false,
`alternative_program_code` nil. `ProgramGroup::DEGREE_LEVELS` gains `certificate`; a
`.badge-certificate` class and an icon mapping follow the existing bachelor/master/doctoral ones.

## Matching (the classifier)

Runs over every parsed line, in this order; the first rule that fires wins. "Pool" = students
whose programme group and admission year equal the line's cohort (CT lines use the CS group).
Names compare on Thai first/last after title stripping; `normalize` strips tone marks and spaces.

0. **Pre-step, CM re-file.** `Student.where(program: 0018, admission_year_be: 2535..2538).where("student_id LIKE 'C%'")`
   → `program: 0037`, remark appended `re-filed from 0018 to 0037: first M.Eng. cohorts (book30 2026-09-14)`.
   Idempotent (no-op once moved). Counted and printed.
1. **unparsed**: fewer than two name tokens after stripping titles and brackets. A line that is
   only a bracketed text is attached as `alias_name` to the previous line instead.
2. **duplicate_line**: same normalized name already seen in the same cohort.
3. **exact**: a pool student with identical `first last`, else identical after `normalize`
   (tone-insensitive). Claim score 0.
4. **near candidates** (one of, in order): unique pool student with the same normalized first
   name → `variant_surname`; pool students with the same normalized surname → the one with the
   smallest first-name edit distance → `variant_firstname`; pool student whose whole normalized
   name is within edit distance 2 → `variant_typo`; a same-group student in another year with
   identical loose name → `other_year` if |Δyear| ≤ 2 else `namesake`; same-group other-year
   student within edit distance 1 → `other_year`/`namesake` by the same year test. Claim score =
   edit distance + 1 (exact always beats near).
5. **Claim resolution**: for each DB student claimed by several lines, the lowest score wins;
   ties → earlier cohort, then earlier line. Winners with an exact claim → `linked_exact`; with
   `other_year` → `linked_other_year`; with a variant → `linked_variant`. Note records which part
   differs, the book year vs DB year, and any track conflict (book CT vs DB regular or reverse).
6. **second_listing**: an unlinked line whose normalized name is already linked under another
   cohort of the same group, or (after creates are assigned) already created under an earlier
   cohort. Note names that cohort. `student_id` points at the same student.
7. **creates**, for the earliest remaining listing of each name within a group:
   `create_namesake` if the only candidate was a namesake; `create_lost_claim` if a near candidate
   was taken by a closer line; `create_book_only_cohort` if the pool is empty; else
   `create_missing`.
8. Cross-cutting notes appended to every line: `also listed under <gens> (other programme)` when
   the same name appears under another group; `maiden/alias in book: <text>`.

Expected dry-run counts on the 2026-09-14 database (after the CM re-file): linked_exact 2,325,
linked_variant 178, linked_other_year 4, second_listing 25, duplicate_line 2,
create_book_only_cohort 1,353, create_missing 102, create_lost_claim 15, create_namesake 2,
unparsed 4; total 4,010; creates 1,472. The implementation must reproduce these within ±3 per
outcome (small differences from the alias-line handling are acceptable and must be explained).

## Constructing a student record from the book

For every `create_*` line:

```
student_id:        "B30-#{cohort}-#{'%03d' % line_no}"
first_name_th/last_name_th: parsed
first_name/last_name:        nil
admission_year_be: cohort year
program:           resolved per the revision rule above (CE → CE2512)
status:            "unknown"
study_track:       "special" (CT) / "regular" (CS, year ≥ 2533) / nil
sex:               from title or nil
source:            "book30"
remark:            "30-year book #{cohort} line #{line_no}: <notes>" truncated to 255
```

## Runner contract

`bin/rails book30:import [PDF=path] [COMMIT=1]` — dry-run by default. Both modes parse, classify
and write `tmp/book30_import/<timestamp>/decisions.csv` (one row per line, same columns as the
log table plus the candidate's name) and `summary.csv` (counts per cohort × outcome), and print the
outcome totals. With `COMMIT=1`, inside one transaction: the CM re-file, then one `Book30Entry`
per line, then new student rows for create outcomes (entry `student_id` set after create).
Refuses to commit if `Book30Entry.any?` — say so and point to `book30:rollback`.

`bin/rails book30:rollback [COMMIT=1]` — deletes all `Book30Entry` rows and all students with
`source = "book30"` (they have no grades or other children by construction; abort if any do).
Does not undo the CM re-file (that is a correction, not part of the import).

`bin/rails book30:report` (existing, read-only reconciliation) keeps working but its default PDF
path is corrected to the renamed file.

## Admin pages

Both under `DataSourcesController`, `before_action :require_admin`, linked as cards/actions from
`/data_sources`:

- `GET /data_sources/book30` — the book import report, live from `book30_entries` and students:
  policy summary, the outcome table with counts and one example per outcome, the per-cohort ledger
  (cohort × outcome counts, DB count, DB-not-in-book computed live), the CE/CM corrections, and
  links to `/students?source=book30` style filters if cheap. Empty state before the import: "No
  book entries yet. Run `bin/rails book30:import COMMIT=1`."
- `GET /data_sources/provenance` — where the data came from: rows-by-source matrix (students by
  `source`, grades by `source`, courses by `auto_generated` + created date, schedule entities by
  scrape), the import-run table from `data_imports`, the scrape table, the timeline (static text),
  known gaps (static text with live numbers where cheap).

Views follow the app's conventions (HAML, Bootstrap dark theme, `.card` + `.card-title`, tables in
cards, semantic `.badge-*` classes, Material Symbols). Charts, if any, go through
`chart_controller.js` (`stacked-bar`). No inline `<script>`; no external assets.

`DataSource::SOURCES` gains a `book30` entry (name "30-Year Anniversary Book", badge `legacy`,
provides / not_provides as in the provenance report, action → the book30 page). The existing
hub page renders it like the others.

Per `docs/backlog.md`, adding report pages triggers the entity→report cross-link review: the
student show page links to the book30 page when the student has a `book30_entries` row (small
"Listed in the 30-year book as <raw_line>, cohort <cohort>" card row).

## Non-goals

- No edits to linked students (names, years, status, track).
- No English-name generation.
- No per-file provenance for the April Excel load (not recoverable).
- No production run in this pass: dev first, dae reviews, then the documented deploy + run.

## Testing

- Model tests: `Book30Entry` validations/outcome constant; `Student` source validation and the
  nullable-English-name rule (`book30` rows valid without English names, `imported` rows still
  require them); `ProgramGroup` accepts `certificate`.
- Service tests with fixtures (no PDF): `Book30::Classifier` given a small synthetic set of parsed
  lines and fixture students exercising each outcome (exact, tone-insensitive, variant surname,
  variant first name, other_year within 2, namesake at 13, lost claim, second listing, duplicate
  line, unparsed, book-only cohort, missing) and the claim resolution. `Book30::Importer` dry-run
  writes nothing; COMMIT creates entries + book-sourced students with the documented attributes and
  student IDs; refuses when entries exist; rollback removes them.
- `Book30::Directory` parsing is covered by a fixture stext XML snippet (two lines, one header,
  one bracket-only continuation) rather than the PDF.
- System test: admin opens `/data_sources/book30` (empty state and populated state) and
  `/data_sources/provenance`; non-admin gets redirected.

## Rollout

Dev: migrate, seed, `book30:import` dry-run → compare with the expected counts → `COMMIT=1` →
regenerate `docs/book30-import-report.md` numbers from the admin page → commit on trunk (explicit
files, Mercurial). Prod later, by dae's go: `hg push`, migrate + seed + assets, run the import with
`COMMIT=1` on the server, verify the admin pages.
