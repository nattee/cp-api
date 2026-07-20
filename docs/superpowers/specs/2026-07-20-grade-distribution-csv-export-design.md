# Grade Distribution CSV Export — Design

**Date**: 2026-07-20
**Status**: Approved

## Goal

Make the grade-distribution report at `/grades/distribution` exportable as CSV.

## Approach

Server-side CSV via `format.csv` on the existing `GradesController#distribution`
action, mirroring the reports-hub pattern (`reports/_result_table` +
`Exporters::ReportExporter`): a plain link carrying the current query params.
No Stimulus changes, no new vendored JS.

Rejected alternatives:

- **Client-side CSV in `datatable_controller.js`** — would respect the
  DataTables search box, but requires bespoke serialization (stripping link
  HTML from cells) and diverges from both existing export conventions.
- **DataTables Buttons extension** — needs a rebuilt vendored UMD bundle plus
  styling work; heaviest option for the same outcome.

## Controller

`GradesController#distribution` gains a `respond_to` block:

- **Both formats** share the existing filter parsing (`@prefix`,
  `@program_code`, `@split`, year range) and `build_distribution_rows`.
- **`format.csv`** skips `build_gpa_trend` (chart data is wasted work for a
  download) and responds with
  `send_data exporter.to_csv, filename:, type: "text/csv", disposition: "attachment"`.
- **`format.html`** behaves exactly as today.

Auth is unchanged: `require_login` applies; the CSV link rides the session.

## Exporter

New `app/services/exporters/grade_distribution_exporter.rb`, following
`ReportExporter`'s shape (`to_csv`, `filename`).

- **Input**: `rows:` (the `@rows` array of hashes), `split:` (boolean).
- **Header**: `Course, Title, [Term — only when split], A, B+, B, C+, C, D+,
  D, F, W, Other, N, GPA, % ≥ C` — mirrors the table's column order.
- **Values**: spreadsheet-friendly. GPA and pass-rate are bare numbers —
  **blank** (not "—") when nil, no `%` sign on the pass rate.
- **Filename**: `grade_distribution.csv` (matches the reports-hub convention
  of a static name per report).

## View

The table card in `app/views/grades/distribution.html.haml` gets the same
title row as `reports/_result_table`:

- `.d-flex.justify-content-between.align-items-center.mb-3` with
  `%h6.card-title.mb-0 Results` on the left.
- On the right, the identical Export CSV button:
  `link_to distribution_grades_path(request.query_parameters.merge(format: :csv))`,
  classes `btn btn-outline-secondary btn-sm`, `download` Material Symbol at
  16px with `vertical-align: middle`.
- The row sits inside the `@rows.present?` branch — no export button when
  there is nothing to export.

## Semantics

The export reflects the **applied** form filters (prefix, program, year range,
split) — exactly the data set the table renders. Text typed into the
DataTables search box is **not** reflected (accepted trade-off of the
server-side approach).

## Testing

Per project convention, ask before writing tests. Natural candidate: an
integration test on `GET /grades/distribution.csv` asserting the header row,
the split/unsplit column variants, and blank-GPA handling.

## Backlog check

`docs/backlog.md` triggers reviewed (this is a changed report): no new
entity→report cross-links or overlap arise from adding an export; item 3's
note on why this page keeps its free-text prefix filter is unaffected.
