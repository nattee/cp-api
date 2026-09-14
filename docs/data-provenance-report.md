# Data Provenance Report

Status: **generated 14 September 2026 from the development database**, which production was copied from on 16 July 2026 and has tracked step for step since. The 30-year book import (`bin/rails book30:import COMMIT=1`) ran on 2026-09-14, on development only — production has not run it yet. Regenerate with `bin/rails runner tmp/provenance_report/scripts/report.rb`. The HTML reading copy is `tmp/provenance_report/report.html`. Live version: `/data_sources/provenance` (admin). The book is now an actual source: see students by source.

## In one paragraph

Everything in cp-api came in through six doors. Registrar Excel extracts, loaded on 12 April 2026, created 7,181 of the 10,093 students (71%) and 31,079 grades. ChulaBooster, the registrar system, was first compared read-only and then allowed to add what it alone knew: 1,440 students, 30,201 grades, 345 courses, and a status-code mirror on 8,575 students. CuGetReg scrapes supplied the whole teaching schedule. Seeds supplied programmes, staff and roles. The 30-year anniversary book, matched line by line against the students table, was imported on 14 September 2026: 1,472 placeholder students from cohorts back to B.E. 2512 that no spreadsheet ever covered. A handful of documented backfills corrected what the imports got wrong.

## Where the rows came from

| Entity | Rows | Excel | ChulaBooster | CuGetReg | Seeds | Book | How to tell |
|---|---|---|---|---|---|---|---|
| Students | 10,093 | 7,181 | 1,440 |  |  | 1,472 | Date created: 12 Apr 2026 is Excel, 5 Jul 2026 is CB, 14 Sep 2026 is the book. A remark beginning ChulaBooster sync marks a heuristic programme assignment. cb_status_code present means CB confirms the student exists. source = book30 marks a book placeholder (student_id shaped B30-<cohort>-<nnn>). |
| Grades | 61,280 | 31,079 | 30,201 |  |  |  | The source column: imported, chulabooster, or manual. |
| Courses | 898 | 553 | 345 |  |  |  | Date created, plus auto_generated: none for a real row, placeholder for a stub the grade import needed, copied for a clone of a neighbouring revision. |
| Programme groups | 9 |  | 1 |  | 7 | 1 | Seven seeded groups plus one created for CB's orphan track. The book adds CE, the certificate programme, created by the 2026-09-14 import. |
| Programmes | 47 |  | 1 |  | 45 | 1 | Seeded with official codes and CB major codes. The book adds revision CE2512, the certificate's non-numeric revision code; every other book cohort reuses an existing revision. |
| Programme-course links | 637 | 553 | 84 |  |  |  | Date created: 1 Jul is the one-to-one backfill from the old courses column, 7 Jul is CB. |
| Staff | 90 |  |  |  | 90 |  | db/seeds/staffs.rb, with the three-letter registrar initials. |
| Course offerings | 2,722 |  |  | 2,722 |  |  | All schedule entities come from scrapes; the Scrape row records term, source and counts. |
| Sections, time slots, teachings, rooms | 23,509 |  |  | 23,509 |  |  | 8,782 sections, 12,224 time slots, 1,894 teachings, 609 rooms. |
| Advisorships | 0 | 0 |  |  |  |  | Importer exists; nothing loaded in this database. |
| Users and roles | 5 |  |  |  | 5 |  | One admin user, four roles. |

## The sources

| Source | How it enters | Provides | Does not provide |
|---|---|---|---|
| Registrar Excel extracts | Eleven spreadsheets handed over between 2020 and 2026: departmental student lists, registrar extracts per degree level, graduate and dismissed lists, and one consolidated all-students file. Loaded through the web import flow (upload, column mapping, execute). | Students with identity, programme, admission year, status, contact fields; one file also carried courses and 33,565 grade rows. | No section links for grades, no schedule data, no alumni before B.E. 2530. Which file created which student is not recorded, only counts per file. |
| ChulaBooster (CB) | The university registrar system, read through a GET-only client. A read-only reconciliation ran first; then additive syncs wrote with COMMIT=1. Local programme identity stays authoritative; CB is authoritative for grades and the better signal for status. | Students CB has that we lacked, their raw status code mirrored onto every matched student, courses, grades, programme-to-course pairings. | Course offerings, sections, rooms, teachers. Current-semester data, since CB lags a term. |
| CuGetReg | The university's course-registration GraphQL API, scraped per term from the web UI at /scrapes. | Semesters, course offerings, sections, time slots, rooms, and teaching assignments matched by staff initials. | Grades, student records, programme structure. |
| Seeds | Hand-authored Ruby files under db/seeds, loaded with db:seed. Institutional knowledge that no external system provides. | Programme groups and programme revisions with official four-digit codes and CB major codes, staff with initials, roles and the admin user. | Anything per student. |
| 30-year anniversary book (legacy) | The department's 30th-anniversary book carries an alumni directory, cohort by cohort, on its last 72 pages. Parsed from the PDF text, matched line by line against the students table, imported 2026-09-14 (development). The first of the legacy sources; more will follow here. | Thai names of alumni from B.E. 2512 onward, including the certificate cohorts and every cohort before 2530 that no spreadsheet covered; a cohort code that fixes programme and admission year. | Student IDs, English names, status, grades, anything after the book went to print in 2548. Its foreword says details were withheld for privacy, so it is not complete either. |
| Backfills and corrections | Console tasks run once, dry-run by default, with a written spec each. | Study track for the M.Sc. CS evening programme, the dissolution of the invented programme 0999, per-pairing course groups, auto-generated course rows promoted to real ones. | New records, apart from placeholders the grade sync needed. |

## Legacy sources

Records that exist on paper or in print rather than in a system. Each is matched against the database before anything is written, and each gets its own report. The book is the first; others will be added here.

| Source | What it is | Coverage | Status | Rows | Report |
|---|---|---|---|---|---|
| 30-year anniversary book | ทำเนียบศิษย์เก่า in book ครบรอบ 30 ปี.pdf, PDF pages 232 to 303, one line per alumnus under a cohort header. | CE 2512 to 2520, CS 2514 to 2548, CP 2517 to 2548, CT 2533 to 2548, CM 2535 to 2548, CD 2541 to 2548, SE 2545 to 2548; 118 cohorts | Imported 2026-09-14 (development database; production not yet run) | 4,010 lines, 4,009 log rows: 2,507 link to existing students, 1,472 become placeholders | `docs/book30-import-report.md` |

## Timeline

- **13 Mar 2026.** A colleague's transcript workbook (Krerk2Nattee-20260313.xlsx) arrives: students, courses, and 33,565 grade rows for 2018 to 2025.
- **1 to 11 Apr 2026.** The importer is built and tuned against the files: combined-name splitting, admission-year derivation, multi-sheet Excel, status and TCAS normalisation, programme-group resolution. Seeds for programmes and staff are written.
- **12 Apr 2026.** The load of record. Thirteen import runs by the admin user: eleven student runs from nine files (one failed attempt on the consolidated file, then success), one course run, one grade run. 7,181 students, 553 courses, 31,079 grades. Seeds give 45 programmes and 90 staff.
- **14 Apr 2026.** Eight CuGetReg scrapes cover 2565/1 to 2568/2: 1,995 course offerings with sections, time slots and rooms.
- **1 Jul 2026.** Courses and programmes become many-to-many; 553 programme-course links are backfilled one-to-one from the old column.
- **2 Jul 2026.** Read-only reconciliation against ChulaBooster: every entity compared, discrepancies written to CSV, nothing changed.
- **5 Jul 2026.** ChulaBooster student sync with COMMIT=1: 1,440 students CB knew and we did not, 726 of them with a heuristic programme assignment recorded in the remark. CB's raw status code is mirrored onto 8,575 students. A local home is created for CB's orphan 2006 track.
- **6 Jul 2026.** ChulaBooster course and grade sync with COMMIT=1: 345 courses and 30,201 grades, plus corrections to auto-generated course rows and stale non-manual grade values.
- **7 Jul 2026.** ChulaBooster programme-course sync adds 84 pairings and group tags; legacy group tags are backfilled.
- **8 to 21 Jul 2026.** CuGetReg scrapes for 2569/1 and 2569/2, then the international programme.
- **16 Jul 2026.** Production database replaced with a copy of this one; every later step ran on both.
- **22 Jul 2026.** Advisorships model and importer added. No rows in this database yet.
- **22 Aug 2026.** Study-track backfill from the department label plus CB fee and study-plan codes; programme 0999 dissolved onto the regular CS lineage. Run identically on development and production.
- **19 to 22 Aug 2026.** The 30-year book's alumni directory is parsed from the PDF and matched against the students table, report only: 4,010 printed lines, 2,311 confirmed at first pass.
- **14 Sep 2026.** The book's cohort codes are identified from its own legend (CE is the pre-department certificate), matching rules are settled, and every line is assigned an outcome: 2,507 links, 1,472 placeholders to create. The same pass revealed 19 first-cohort M.Eng. students filed under the bachelor programme; they are re-filed to CM revision 0037 as the importer's pre-step. `bin/rails book30:import COMMIT=1` runs the same day on development: 1,472 students created, programme group CE and revision CE2512 added. Production has not run it yet.

## The Excel load of 12 April 2026

File-name prefixes are the year of the extract in the Christian era (20 = 2020, 21 = 2021, 24 = 2024, 25 = 2025); 00 is the consolidated all-students file. All runs used upsert mode, so a student present in several files was created by the first and updated by the later ones.

| # | Target | File | Rows | Created | Updated | Unchanged | Skipped | State |
|---|---|---|---|---|---|---|---|---|
| 1 | Student | 20-ข้อมูลนิสิตปัจจุบันภาควิชาฯ-20-10-2563.xlsx | 845 | 489 | 0 | 283 | 73 | completed |
| 2 | Student | 21-0810_21_ข้อมูลนิสิตภาควิชาวิศวกรรมคอมพิวเตอร์_ปริญญาตรี.xlsx | 1,024 | 54 | 69 | 901 | 0 | completed |
| 3 | Student | 21-0810_21_ข้อมูลนิสิตภาควิชาวิศวกรรมคอมพิวเตอร์_ปริญญาโท.xlsx | 982 | 535 | 119 | 328 | 0 | completed |
| 4 | Student | 21-0810_21_ข้อมูลนิสิตภาควิชาวิศวกรรมคอมพิวเตอร์_ปริญญาเอก.xlsx | 71 | 34 | 36 | 1 | 0 | completed |
| 5 | Student | 24-0910_21_com-eng-no-pass.xlsx | 1,441 | 205 | 137 | 1,099 | 0 | completed |
| 6 | Student | 25-0725_21_CompEng grad & dismissed (update from 240910).xlsx | 657 | 132 | 525 | 0 | 0 | completed |
| 7 | Student | 25-beng-ข้อมูลนิสิตระดับปริญญาตรี ประจำปีการศึกษา 2568.xlsx | 1,879 | 447 | 874 | 558 | 0 | completed |
| 8 | Student | 25-grad-ข้อมูลนิสิตระดับบัณฑิตศึกษา ประจำปีการศึกษา 2568.xlsx | 729 | 1 | 89 | 639 | 0 | completed |
| 9 | Student | Krerk2Nattee-20260313.xlsx | 1,113 | 26 | 973 | 114 | 0 | completed |
| 10 | Student | 00-bigfile-รวมนิสิตทั้งหมด-ถึง2567 ภาคต้น-17-6-2568.xlsx | 3,542 | 0 | 0 | 0 | 0 | failed |
| 11 | Student | 00-bigfile-รวมนิสิตทั้งหมด-ถึง2567 ภาคต้น-17-6-2568.xlsx | 3,542 | 3,372 | 170 | 0 | 0 | completed |
| 12 | Course | Krerk2Nattee-20260313.xlsx | 172 | 171 | 1 | 0 | 0 | completed |
| 13 | Grade | Krerk2Nattee-20260313.xlsx | 33,565 | 31,079 | 7 | 29 | 2,450 | completed |

## ChulaBooster, reconciled then synced

- **Read-only first.** The reconciliation of 2 July 2026 compared programmes, courses, students, grades and pairings and wrote discrepancy CSVs. Its findings are in `docs/chulabooster-program-crosswalk.md` (CB's programme identifiers are coarser than ours, so local programme identity stays authoritative) and `docs/chulabooster-student-status-crosswalk.md` (for status the authority flips: CB is the better signal).
- **Students, 5 July.** 1,440 students created, by group: 21103 9, CD 62, CEDT 20, CM 215, CP 229, CS 685, SE 220. 726 carry a remark explaining a heuristic programme choice. No existing student's programme was touched. cb_status_code mirrored onto 8,575 students.
- **Courses and grades, 6 July.** 345 courses (180 none, 145 placeholder, 20 copied) and 30,201 grades with source chulabooster. Grade identity is student, course number, year and semester, revision-insensitive.
- **Pairings, 7 July.** 84 programme-course links and group tags.

Grades by year and source (imported = Excel, chulabooster = CB):

| Year | Excel | ChulaBooster |
|---|---|---|
| 2016 | 0 | 4 |
| 2017 | 0 | 10 |
| 2018 | 44 | 24 |
| 2019 | 151 | 31 |
| 2020 | 2,150 | 59 |
| 2021 | 4,158 | 90 |
| 2022 | 6,009 | 323 |
| 2023 | 7,522 | 4,084 |
| 2024 | 7,646 | 8,660 |
| 2025 | 3,399 | 16,916 |

Students with any grade: 1,977 (Excel grades cover 799 students, CB grades 1,691).

## Schedule scrapes

| # | Date | Term | Programme | Courses found | State |
|---|---|---|---|---|---|
| 1 | 2026-04-14 | 2568/2 | S | 377 of 553 | completed |
| 2 | 2026-04-14 | 2568/1 | S | 394 of 553 | completed |
| 3 | 2026-04-14 | 2567/2 | S | 373 of 553 | completed |
| 4 | 2026-04-14 | 2567/1 | S | 354 of 553 | completed |
| 5 | 2026-04-14 | 2566/2 | S | 343 of 553 | completed |
| 6 | 2026-04-14 | 2566/1 | S | 337 of 553 | completed |
| 7 | 2026-04-14 | 2565/1 | S | 329 of 553 | completed |
| 8 | 2026-04-14 | 2565/2 | S | 343 of 553 | completed |
| 9 | 2026-07-08 | 2569/2 | S | 2 of 5 | completed |
| 10 | 2026-07-08 | 2569/2 | S | 481 of 898 | completed |
| 11 | 2026-07-09 | 2569/1 | S | 487 of 898 | completed |
| 12 | 2026-07-21 | 2569/1 | I | 47 of 898 | completed |
| 13 | 2026-07-21 | 2569/2 | I | 42 of 898 | completed |

Offerings per term: 2565/1 233, 2565/2 236, 2566/1 238, 2566/2 240, 2567/1 253, 2567/2 260, 2568/1 279, 2568/2 256, 2569/1 371, 2569/2 356.

## Reading a student row

- Created 12 Apr 2026: from Excel. Created 5 Jul 2026: from CB. Created 14 Sep 2026: from the book (source book30).
- Student ID shape: 10-digit 7,795, 7-digit 446, C-prefixed 380, B30-prefixed 1,472. Ten digits is the modern registrar ID, seven digits the pre-2540 bachelor ID, a C prefix the graduate-school ID of the 2530s, B30-<cohort>-<nnn> a book placeholder with no real registrar ID.
- Admission years 2512 to 2568. Below 2530 is book-only (CE 2512–2520, CS/CP back to 2514/2517); nothing there came from Excel or CB.
- Status by origin: 12 Apr active 1,587, 12 Apr graduated 4,729, 12 Apr retired 820, 12 Apr unknown 45, 5 Jul active 33, 5 Jul graduated 464, 5 Jul retired 943, 14 Sep unknown 1,472 (the book only says "ever studied", never "graduated").
- Study track: unset 6,718, special 1,343, regular 560. Set by the 22 Aug backfill for the CS, SE and CM master's groups.

## Known gaps

- No per-row link from a student to the Excel file that created it. The import table keeps counts per file only. Since the same student often appeared in several files, the last upsert wins and the trail is lost.
- Status was set to active by default at import and never re-confirmed for Excel rows. CB's status code is the more reliable signal; the 80 discrepancies found in July were resolved by hand, and the mirror column remains for future checks.
- 8,116 of 10,093 students have no grades at all (6,644 pre-book, plus all 1,472 book placeholders, which carry no grades by design). Grade data exists only for 2016 to 2025, so it covers recent students and nothing of the alumni body.
- 468 of 898 course rows are machine-made stubs or clones created so a grade could attach. They carry auto_generated other than none until a real revision replaces them.
- 46 Excel-created students are unknown to ChulaBooster. They may predate CB's coverage or carry a different identifier.
- One junk course row: course number "ETL" with revision year 543, a year-zero conversion artefact.
- The consolidated all-students file listed major names only. Programme resolution picked the latest revision at or before the admission year, which invented programme 0999 for 730 students; dissolved on 22 Aug 2026.
- Grades carry no section link; grades.section_id is null everywhere.
- 19 first-cohort M.Eng. students (2535 to 2538) sat under the bachelor programme with graduate-school IDs. Found 14 Sep 2026; re-filed to CM revision 0037 the same day, as the book import's pre-step.

## Related documents

`docs/chulabooster-program-crosswalk.md`, `docs/chulabooster-student-status-crosswalk.md`, `docs/chulabooster-client-guide.md`, `docs/schedule-scraper.md`, `docs/superpowers/specs/2026-08-21-cs-study-track-design.md`, `docs/book30-import-report.md`, and the admin page at /data_sources, whose text lives in `DataSource::SOURCES`.
