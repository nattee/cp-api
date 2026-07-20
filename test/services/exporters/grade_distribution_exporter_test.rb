require "test_helper"

class Exporters::GradeDistributionExporterTest < ActiveSupport::TestCase
  # Exports start with a UTF-8 BOM (the "% ≥ C" header would otherwise mangle
  # in Excel on a non-UTF-8 locale). Strip it before parsing or the first
  # header cell reads "﻿Course".
  def parse(csv_string)
    CSV.parse(csv_string.delete_prefix(Exporters::Base::BOM))
  end

  def sample_row(overrides = {})
    {
      course_no: "2110101",
      title: "Introduction to Computing",
      term_key: [2024, 1],
      term: "2024/1",
      buckets: { "A" => 5, "B+" => 2, "B" => 1, "C+" => 0, "C" => 3,
                 "D+" => 0, "D" => 0, "F" => 1, "W" => 2 },
      other: 1,
      n: 15,
      gpa: 3.12,
      pass_rate: 92
    }.merge(overrides)
  end

  test "export starts with a UTF-8 BOM so Excel reads the ≥ header correctly" do
    csv = Exporters::GradeDistributionExporter.new(rows: [sample_row], split: true).to_csv
    assert csv.start_with?(Exporters::Base::BOM), "CSV must lead with the UTF-8 BOM"
  end

  test "split export mirrors the table's column order" do
    csv = parse(Exporters::GradeDistributionExporter.new(rows: [sample_row], split: true).to_csv)
    assert_equal ["Course", "Title", "Term", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    assert_equal ["2110101", "Introduction to Computing", "2024/1",
                  "5", "2", "1", "0", "3", "0", "0", "1", "2", "1", "15", "3.12", "92"], csv[1]
  end

  test "unsplit export omits the Term column" do
    exporter = Exporters::GradeDistributionExporter.new(
      rows: [sample_row(term: nil, term_key: nil)], split: false
    )
    csv = parse(exporter.to_csv)
    assert_equal ["Course", "Title", "A", "B+", "B", "C+", "C", "D+", "D", "F",
                  "W", "Other", "N", "GPA", "% ≥ C"], csv[0]
    assert_equal "5", csv[1][2], "A-count should directly follow Title when unsplit"
  end

  test "titles containing commas and quotes are CSV-escaped" do
    exporter = Exporters::GradeDistributionExporter.new(
      rows: [sample_row(title: 'Intro, to "Computing"')], split: true
    )
    assert_equal 'Intro, to "Computing"', parse(exporter.to_csv)[1][1]
  end

  test "an empty result set still produces a header-only CSV" do
    csv = parse(Exporters::GradeDistributionExporter.new(rows: [], split: true).to_csv)
    assert_equal 1, csv.size
    assert_equal "Course", csv[0][0]
  end

  test "nil GPA and pass rate export as blank cells, not em-dashes" do
    exporter = Exporters::GradeDistributionExporter.new(
      rows: [sample_row(gpa: nil, pass_rate: nil)], split: true
    )
    csv = parse(exporter.to_csv)
    assert_nil csv[1][-2]
    assert_nil csv[1][-1]
  end

  test "filename is the static report name" do
    assert_equal "grade_distribution.csv",
                 Exporters::GradeDistributionExporter.new(rows: [], split: true).filename
  end
end
