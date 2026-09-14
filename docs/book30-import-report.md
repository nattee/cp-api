# 30th-Anniversary Book: Alumni Directory Import Report

Status: **imported, 2026-09-14.** `bin/rails book30:import COMMIT=1` ran on the development
database; logs in `tmp/book30_import/20260914-164537/` (the dry run, `tmp/book30_import/20260914-164326/`,
produced identical numbers). The PDF prints 4,010 lines in the student sections; one of them is a
bracket-only maiden-name continuation that gets folded into the previous line's alias instead of
logged on its own, so the import log holds 4,009 rows. Outcomes: `linked_exact` 2,325,
`linked_variant` 178, `linked_other_year` 4, `second_listing` 25, `duplicate_line` 2, `unparsed` 3,
`create_book_only_cohort` 1,353, `create_missing` 102, `create_lost_claim` 15, `create_namesake` 2.
1,472 placeholders created: CE 666, CS 418, CT 25, CP 353, SE 9, CD 1. Programme revisions used:
1027 ×393, 0038 ×50, 0018 ×344, 0928 ×6, 0779 ×3, CE2512 ×666, 0772 ×9, 0458 ×1. The 19 CM01–CM04
students were re-filed from program 0018 to 0037 as the importer's pre-step. Students now 10,093
(imported 7,181 / chulabooster 1,440 / book30 1,472). DB students in book cohorts that no book line
claimed: 224. Live version: `/data_sources/book30` (admin).

## Source

The department's 30-year anniversary book (`book ครบรอบ 30 ปี.pdf`, 303 pages) carries an alumni
directory on PDF pages 232–303: names grouped under cohort headers `รุ่น <CODE><NN>`. The book's own
legend on page 231 defines the codes and each program's first intake (B.E.):

| Code | Program | First intake |
|---|---|---|
| CE | ประกาศนียบัตรคอมพิวเตอร์ไซแอนส์ (certificate, non-degree, pre-department, last cohort CE09 = 2520) | 2512 |
| CS | ปริญญาโท วิทยาศาสตร์คอมพิวเตอร์ (วท.ม.) | 2514 |
| CP | ปริญญาตรี วิศวกรรมคอมพิวเตอร์ (วศ.บ.) | 2517 |
| CT | ปริญญาโท วิทยาศาสตร์คอมพิวเตอร์ ภาคนอกเวลาราชการ (วท.ม.) — same DB group as CS, `study_track = special` | 2533 |
| CM | ปริญญาโท วิศวกรรมคอมพิวเตอร์ (วศ.ม.) | 2535 |
| CD | ปริญญาเอก วิศวกรรมคอมพิวเตอร์ (วศ.ด.) | 2541 |
| SE | ปริญญาโท วิศวกรรมซอฟต์แวร์ (วท.ม.) | 2545 |

Cohort NN enrolled in `first_intake + NN − 1`. Faculty (AJ) and staff (AS) sections are skipped.
The book prints a title and a Thai name only: no student ID, no English name, no year beyond the cohort.
Some lines carry a maiden name in brackets.

## Policy (decided 2026-09-14)

1. **Cohort with book data and no DB students → believe the book.** Create a placeholder student
   for every name.
2. **Odd cases (double listings, two book names on one DB student, year disagreements) → apply the
   mechanical rule below and log it**, so the decision can be amended if new information arrives.
3. **Cohort present in both, majority of names matching → the DB is authoritative.** A near match is
   linked to the existing student; DB names and years are never edited; the book's variant is logged.
   No human review of near matches: there is no practical way to verify them without direct labour.

Rules apply **per book line**, not per cohort. Every line receives exactly one outcome below. Every
line, whatever its outcome, gets one row in the import log (cohort, raw line, parsed name, outcome,
linked or created student, note). Names confirmed anywhere in the book are never created a second time.

## Pre-import DB correction (needs approval before the run)

The book's CM01–CM04 (2535–2538, 19 names) looked like a book-only cohort, but all 19 people exist in
the DB with graduate-school IDs `C5187xx`–`C8188xx`, filed under **CP program 0018** (the bachelor
revision), mostly status `retired`. 18 match the book exactly, 1 differs by a missing ์. They are the
first four CM cohorts and belong on CM revision **0037** (year 2535). Without this re-file the import
would create 19 duplicate CM placeholders and leave 19 phantom CP students. All counts below assume
the re-file is done first.

## Outcomes

| # | Outcome | Lines | What it means | Action | Log note |
|---|---|---|---|---|---|
| 1 | `linked_exact` | 2,325 | The book name equals a DB student's Thai name in the same program and admission year. 11 of these differ only in tone marks. 11 are book-CT-vs-DB-regular or the reverse. | Link. No change to the student. | Track conflict, if any. |
| 2 | `linked_variant` | 178 | Same cohort, one part of the name matches, the other differs. 107 surname differs with a unique first name (typos, marriages; 5 confirmed by a bracketed maiden name). 63 first name differs with the same surname (typos, first-name changes). 8 whole-name edit distance ≤ 2. | Link. DB name kept. | Which part differs; book spelling; maiden name. |
| 3 | `linked_other_year` | 4 | Same name in the same program, DB admission year 1–2 years from the book cohort, after double listings are removed. | Link. DB year kept. | Book year vs DB year. |
| 4 | `second_listing` | 25 | The same name appears under two cohorts of one program. 23: another listing is already linked to a DB student (6 of those people genuinely have two DB rows from re-admission). 2: another listing already produced the placeholder. | Nothing. | Which cohort holds the linked or created row. |
| 5 | `duplicate_line` | 2 | The identical line is printed twice in one cohort. | Nothing. | — |
| 6 | `create_book_only_cohort` | 1,353 | The cohort has no DB students at all: CE01–CE09 (666), CP01–CP13, CS01–CS17, plus the lone CS18. | Create placeholder. | Cohort. |
| 7 | `create_missing` | 102 | The cohort has DB students but no candidate for this name by any rule. Mostly CS regular 2532–2548 (59) and CT (22). | Create placeholder. | — |
| 8 | `create_lost_claim` | 15 | The near-match rule pointed at a DB student that a closer book name also claims. The closer name keeps the link. Some are probably the same woman under maiden and married name; the resulting duplicate is accepted and reversible. | Create placeholder. | The DB student that was taken, and by whom. |
| 9 | `create_namesake` | 2 | The only same-name DB student entered 13 years away from the book cohort. Treated as a different person. | Create placeholder. | The namesake's ID and year. |
| 10 | `unparsed` | 4 | Three lines print a first name only (เอนก CP13, ประเสริฐศักดิ์ CP25, จตุพร CS04); one is a bracketed maiden name printed on its own line (วันเพ็ญ ฆนวารี CP19, belongs to the line above). | Nothing by default; hand fix in the parser if wanted. | Raw line. |
| 11 | `db_not_in_book` | 224 | A DB student in a book cohort that no book line linked to (CP 65, CS 67, CT 59, CM 18, SE 9, CD 6; 125 graduated, 99 retired). The book is not complete: its foreword says details were withheld to protect personal data. | Nothing. | Status and track. |

Lines 1–10 sum to the 4,010 lines in the student sections. Creates total **1,472**: CE 666, CS 418,
CP 353, CT 25, SE 9, CD 1. Links total 2,507.

Cross-cutting annotations, not outcomes: 123 people appear under two different programs (63 CP+CM,
the bachelor-then-master pattern); the DB already keeps one row per enrollment, so each listing is
handled on its own and the log notes the other cohorts. Sex is known from the title for 1,341 of the
1,472 creates (นาย → male; นาง, นางสาว → female).

## Placeholder shape (open decisions, recommendations as of 2026-09-14)

| Field | Recommendation |
|---|---|
| `student_id` | Synthetic, non-numeric, derived from the book position (cohort code + sequence) so re-runs are idempotent; replaced when a real ID surfaces. |
| `first_name`, `last_name` (English) | Make nullable; do not transliterate or copy Thai. |
| `first_name_th`, `last_name_th` | From the book, titles stripped. |
| `program` | CE → new CE program group (certificate level) with one revision row under the same synthetic-code convention. CP01–CP02 → revision 0018 (2519), CS01–CS10 → revision 1027 (2524), with a remark, unless official codes are known. |
| `admission_year_be` | From the cohort code. |
| `status` | `unknown` (the book says "ever studied", not "graduated"). |
| `study_track` | `special` for CT cohorts, `regular` for CS cohorts from 2533 on. |
| `sex` | From the title when present. |
| `source` | New column marking book-derived rows (like `grades.source`). |
| `remark` | Maiden name, second cohort, namesake or lost-claim reference. |

## Per-cohort outcomes

Counts per cohort of every outcome above (pre-import dry run, CM re-file simulated). `DB` = students in that
program and admission year, CS/CT split by study track. `DB only` = outcome 11. Regenerate with
`bin/rails runner tmp/book30_report/scripts/cohort_outcomes.rb`.

| Cohort | Year | Book | DB | Exact | Variant | Other yr | 2nd list | Dup line | Create: cohort | Create: missing | Create: lost claim | Create: namesake | Unparsed | DB only |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CE01 | 2512 | 138 |  |  |  |  |  |  | 138 |  |  |  |  |  |
| CE02 | 2513 | 23 |  |  |  |  |  |  | 23 |  |  |  |  |  |
| CE03 | 2514 | 23 |  |  |  |  |  |  | 23 |  |  |  |  |  |
| CE04 | 2515 | 58 |  |  |  |  |  |  | 58 |  |  |  |  |  |
| CE05 | 2516 | 73 |  |  |  |  |  |  | 73 |  |  |  |  |  |
| CE06 | 2517 | 118 |  |  |  |  |  |  | 118 |  |  |  |  |  |
| CE07 | 2518 | 50 |  |  |  |  |  |  | 50 |  |  |  |  |  |
| CE08 | 2519 | 76 |  |  |  |  |  |  | 76 |  |  |  |  |  |
| CE09 | 2520 | 107 |  |  |  |  |  |  | 107 |  |  |  |  |  |
| **CE total** | | **666** | **0** | **0** | **0** | **0** | **0** | **0** | **666** | **0** | **0** | **0** | **0** | **0** |
| CS01 | 2514 | 14 |  |  |  |  |  |  | 14 |  |  |  |  |  |
| CS02 | 2515 | 21 |  |  |  |  |  |  | 21 |  |  |  |  |  |
| CS03 | 2516 | 27 |  |  |  |  |  |  | 27 |  |  |  |  |  |
| CS04 | 2517 | 24 |  |  |  |  |  |  | 23 |  |  |  | 1 |  |
| CS05 | 2518 | 22 |  |  |  |  |  |  | 22 |  |  |  |  |  |
| CS06 | 2519 | 25 |  |  |  |  |  |  | 25 |  |  |  |  |  |
| CS07 | 2520 | 28 |  |  |  |  |  |  | 28 |  |  |  |  |  |
| CS08 | 2521 | 24 |  |  |  |  |  |  | 24 |  |  |  |  |  |
| CS09 | 2522 | 27 |  |  |  |  | 1 |  | 26 |  |  |  |  |  |
| CS10 | 2523 | 20 |  |  |  |  |  |  | 20 |  |  |  |  |  |
| CS11 | 2524 | 25 |  |  |  |  |  |  | 25 |  |  |  |  |  |
| CS12 | 2525 | 9 |  |  |  |  |  |  | 9 |  |  |  |  |  |
| CS13 | 2526 | 19 |  |  |  |  |  | 1 | 17 |  |  | 1 |  |  |
| CS14 | 2527 | 13 |  |  |  |  | 1 |  | 12 |  |  |  |  |  |
| CS15 | 2528 | 21 |  |  |  |  |  |  | 21 |  |  |  |  |  |
| CS16 | 2529 | 20 |  |  |  |  |  |  | 20 |  |  |  |  |  |
| CS17 | 2530 | 21 |  |  |  |  |  |  | 21 |  |  |  |  |  |
| CS18 | 2531 | 21 | 1 |  |  |  |  |  |  | 21 |  |  |  | 1 |
| CS19 | 2532 | 26 | 31 | 22 | 3 |  | 1 |  |  |  |  |  |  | 6 |
| CS20 | 2533 | 22 | 24 | 13 | 6 |  |  |  |  | 3 |  |  |  | 3 |
| CS21 | 2534 | 24 | 24 | 18 | 5 |  |  |  |  | 1 |  |  |  | 1 |
| CS22 | 2535 | 27 | 29 | 15 | 9 |  |  |  |  | 3 |  |  |  | 3 |
| CS23 | 2536 | 22 | 21 | 17 | 3 |  |  |  |  | 2 |  |  |  |  |
| CS24 | 2537 | 21 | 18 | 11 | 7 |  |  |  |  | 3 |  |  |  |  |
| CS25 | 2538 | 22 | 20 | 18 | 2 |  |  |  |  | 1 | 1 |  |  |  |
| CS26 | 2539 | 6 | 23 | 5 | 1 |  |  |  |  |  |  |  |  | 17 |
| CS27 | 2540 | 29 | 24 | 19 | 4 | 1 |  |  |  | 5 |  |  |  | 1 |
| CS28 | 2541 | 38 | 32 | 25 | 5 | 1 | 1 |  |  | 5 | 1 |  |  | 2 |
| CS29 | 2542 | 23 | 20 | 16 | 3 |  |  |  |  | 4 |  |  |  |  |
| CS30 | 2543 | 25 | 21 | 19 | 2 |  |  |  |  | 4 |  |  |  |  |
| CS31 | 2544 | 10 | 28 | 6 | 2 | 1 | 1 |  |  |  |  |  |  | 20 |
| CS32 | 2545 | 26 | 28 | 19 | 2 |  |  |  |  | 5 |  |  |  | 6 |
| CS33 | 2546 | 29 | 32 | 23 | 6 |  |  |  |  |  |  |  |  | 2 |
| CS34 | 2547 | 19 | 19 | 15 | 2 |  |  |  |  | 2 |  |  |  | 2 |
| CS35 | 2548 | 23 | 25 | 21 | 1 |  |  |  |  |  |  | 1 |  | 3 |
| **CS total** | | **773** | **420** | **282** | **63** | **3** | **5** | **1** | **355** | **59** | **2** | **2** | **1** | **67** |
| CP01 | 2517 | 19 |  |  |  |  |  |  | 19 |  |  |  |  |  |
| CP02 | 2518 | 20 |  |  |  |  |  |  | 20 |  |  |  |  |  |
| CP03 | 2519 | 15 |  |  |  |  |  |  | 15 |  |  |  |  |  |
| CP04 | 2520 | 15 |  |  |  |  |  |  | 15 |  |  |  |  |  |
| CP05 | 2521 | 16 |  |  |  |  |  |  | 16 |  |  |  |  |  |
| CP06 | 2522 | 19 |  |  |  |  |  |  | 19 |  |  |  |  |  |
| CP07 | 2523 | 19 |  |  |  |  |  |  | 19 |  |  |  |  |  |
| CP08 | 2524 | 38 |  |  |  |  |  |  | 38 |  |  |  |  |  |
| CP09 | 2525 | 37 |  |  |  |  |  |  | 37 |  |  |  |  |  |
| CP10 | 2526 | 37 |  |  |  |  |  |  | 37 |  |  |  |  |  |
| CP11 | 2527 | 32 |  |  |  |  |  |  | 32 |  |  |  |  |  |
| CP12 | 2528 | 33 |  |  |  |  |  |  | 33 |  |  |  |  |  |
| CP13 | 2529 | 33 |  |  |  |  |  |  | 32 |  |  |  | 1 |  |
| CP14 | 2530 | 40 | 37 | 30 | 7 |  |  |  |  | 3 |  |  |  |  |
| CP15 | 2531 | 37 | 35 | 29 | 5 |  |  |  |  | 3 |  |  |  | 1 |
| CP16 | 2532 | 48 | 48 | 44 | 4 |  |  |  |  |  |  |  |  |  |
| CP17 | 2533 | 52 | 51 | 50 | 1 |  |  |  |  | 1 |  |  |  |  |
| CP18 | 2534 | 59 | 56 | 52 | 4 |  | 2 |  |  |  | 1 |  |  |  |
| CP19 | 2535 | 56 | 50 | 48 | 1 |  | 5 |  |  |  | 1 |  | 1 | 1 |
| CP20 | 2536 | 51 | 51 | 43 | 8 |  |  |  |  |  |  |  |  |  |
| CP21 | 2537 | 60 | 55 | 55 |  |  | 2 |  |  |  | 3 |  |  |  |
| CP22 | 2538 | 65 | 63 | 62 | 1 |  | 2 |  |  |  |  |  |  |  |
| CP23 | 2539 | 104 | 100 | 93 | 7 |  | 3 | 1 |  |  |  |  |  |  |
| CP24 | 2540 | 97 | 95 | 88 | 7 |  | 1 |  |  |  | 1 |  |  |  |
| CP25 | 2541 | 104 | 101 | 94 | 5 |  | 1 |  |  | 1 | 2 |  | 1 | 2 |
| CP26 | 2542 | 106 | 104 | 103 | 1 |  |  |  |  |  | 2 |  |  |  |
| CP27 | 2543 | 103 | 103 | 101 | 2 |  |  |  |  |  |  |  |  |  |
| CP28 | 2544 | 110 | 110 | 110 |  |  |  |  |  |  |  |  |  |  |
| CP29 | 2545 | 98 | 98 | 97 | 1 |  |  |  |  |  |  |  |  |  |
| CP30 | 2546 | 101 | 100 | 98 | 2 |  |  |  |  | 1 |  |  |  |  |
| CP31 | 2547 | 98 | 96 | 96 |  |  |  |  |  | 2 |  |  |  |  |
| CP32 | 2548 | 46 | 107 | 46 |  |  |  |  |  |  |  |  |  | 61 |
| **CP total** | | **1768** | **1460** | **1339** | **56** | **0** | **16** | **1** | **332** | **11** | **10** | **0** | **3** | **65** |
| CT01 | 2533 | 26 | 28 | 21 | 3 |  |  |  |  | 2 |  |  |  | 6 |
| CT02 | 2534 | 42 | 44 | 36 | 4 |  | 1 |  |  |  | 1 |  |  | 4 |
| CT03 | 2535 | 29 | 29 | 27 | 2 |  |  |  |  |  |  |  |  | 2 |
| CT04 | 2536 | 37 | 35 | 32 | 4 |  |  |  |  | 1 |  |  |  |  |
| CT05 | 2537 | 26 | 27 | 20 | 6 |  |  |  |  |  |  |  |  | 1 |
| CT06 | 2538 | 31 | 30 | 29 | 1 |  |  |  |  | 1 |  |  |  |  |
| CT07 | 2539 | 27 | 31 | 23 | 3 |  |  |  |  |  | 1 |  |  | 4 |
| CT08 | 2540 | 33 | 38 | 27 | 2 |  |  |  |  | 4 |  |  |  | 9 |
| CT09 | 2541 | 42 | 38 | 29 | 5 | 1 | 1 |  |  | 6 |  |  |  | 3 |
| CT10 | 2542 | 31 | 31 | 28 | 3 |  |  |  |  |  |  |  |  |  |
| CT11 | 2543 | 32 | 27 | 21 | 3 |  |  |  |  | 8 |  |  |  | 3 |
| CT12 | 2544 | 16 | 29 | 12 | 4 |  |  |  |  |  |  |  |  | 13 |
| CT13 | 2545 | 22 | 32 | 19 | 3 |  |  |  |  |  |  |  |  | 10 |
| CT14 | 2546 | 31 | 30 | 26 | 2 |  | 2 |  |  |  | 1 |  |  | 3 |
| CT15 | 2547 | 24 | 24 | 24 |  |  |  |  |  |  |  |  |  |  |
| CT16 | 2548 | 25 | 26 | 25 |  |  |  |  |  |  |  |  |  | 1 |
| **CT total** | | **474** | **499** | **399** | **45** | **1** | **4** | **0** | **0** | **22** | **3** | **0** | **0** | **59** |
| CM01 | 2535 | 6 | 6 | 5 | 1 |  |  |  |  |  |  |  |  |  |
| CM02 | 2536 | 6 | 6 | 6 |  |  |  |  |  |  |  |  |  |  |
| CM03 | 2537 | 2 | 2 | 2 |  |  |  |  |  |  |  |  |  |  |
| CM04 | 2538 | 5 | 5 | 5 |  |  |  |  |  |  |  |  |  |  |
| CM05 | 2539 | 4 | 4 | 4 |  |  |  |  |  |  |  |  |  |  |
| CM06 | 2540 | 5 | 5 | 5 |  |  |  |  |  |  |  |  |  |  |
| CM07 | 2541 | 14 | 14 | 14 |  |  |  |  |  |  |  |  |  |  |
| CM08 | 2542 | 18 | 18 | 18 |  |  |  |  |  |  |  |  |  |  |
| CM09 | 2543 | 6 | 6 | 6 |  |  |  |  |  |  |  |  |  |  |
| CM10 | 2544 | 11 | 15 | 11 |  |  |  |  |  |  |  |  |  | 4 |
| CM11 | 2545 | 17 | 17 | 16 | 1 |  |  |  |  |  |  |  |  |  |
| CM12 | 2546 | 22 | 25 | 20 | 2 |  |  |  |  |  |  |  |  | 3 |
| CM13 | 2547 | 28 | 28 | 28 |  |  |  |  |  |  |  |  |  |  |
| CM14 | 2548 | 24 | 35 | 23 | 1 |  |  |  |  |  |  |  |  | 11 |
| **CM total** | | **168** | **186** | **163** | **5** | **0** | **0** | **0** | **0** | **0** | **0** | **0** | **0** | **18** |
| CD01 | 2541 | 8 | 8 | 8 |  |  |  |  |  |  |  |  |  |  |
| CD02 | 2542 | 2 | 2 | 2 |  |  |  |  |  |  |  |  |  |  |
| CD03 | 2543 | 7 | 7 | 7 |  |  |  |  |  |  |  |  |  |  |
| CD04 | 2544 | 7 | 7 | 7 |  |  |  |  |  |  |  |  |  |  |
| CD05 | 2545 | 5 | 5 | 4 |  |  |  |  |  | 1 |  |  |  | 1 |
| CD06 | 2546 | 10 | 10 | 9 | 1 |  |  |  |  |  |  |  |  |  |
| CD07 | 2547 | 18 | 18 | 16 | 2 |  |  |  |  |  |  |  |  |  |
| CD08 | 2548 | 9 | 14 | 9 |  |  |  |  |  |  |  |  |  | 5 |
| **CD total** | | **66** | **71** | **62** | **3** | **0** | **0** | **0** | **0** | **1** | **0** | **0** | **0** | **6** |
| SE01 | 2545 | 25 | 26 | 23 | 1 |  |  |  |  | 1 |  |  |  | 2 |
| SE02 | 2546 | 21 | 24 | 19 | 2 |  |  |  |  |  |  |  |  | 3 |
| SE03 | 2547 | 22 | 23 | 19 | 2 |  |  |  |  | 1 |  |  |  | 2 |
| SE04 | 2548 | 27 | 22 | 19 | 1 |  |  |  |  | 7 |  |  |  | 2 |
| **SE total** | | **95** | **95** | **80** | **6** | **0** | **0** | **0** | **0** | **9** | **0** | **0** | **0** | **9** |
| **All** | | **4010** | **2731** | **2325** | **178** | **4** | **25** | **2** | **1353** | **102** | **15** | **2** | **4** | **224** |

## Files

`tmp/book30_report/decisions.csv` is the dry run's one-row-per-line log. `cohort_table.html`,
`competing_examples.html` and the `scripts/` folder hold the analysis behind these numbers.
`bin/rails book30:report` (needs `PDF=` since the file was renamed) regenerates the August match report.
The actual commit run's logs are `tmp/book30_import/20260914-164537/decisions.csv` and
`summary.csv` (dry run at `tmp/book30_import/20260914-164326/`, same numbers). All of these `tmp/`
files are scratch and hg-ignored — the app pages (`/data_sources/book30`, `/data_sources/provenance`)
supersede them as the live, browsable version; regenerate the `tmp/` files only for one-off analysis.
