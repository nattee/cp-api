require "test_helper"
require "roo"

class Exporters::StudentExporterTest < ActiveSupport::TestCase
  # Mirrors the relation the controller builds (eager-loads program group so
  # name_en / degree_level don't N+1, and so the columns resolve).
  def relation(scope = Student.all)
    scope.left_joins(program: :program_group)
         .includes(program: :program_group)
         .references(:program_groups)
  end

  # Parse the exporter's XLSX back into rows keyed by header.
  def parsed_rows(exporter)
    Tempfile.create(["students", ".xlsx"]) do |f|
      f.binmode
      f.write(exporter.to_xlsx)
      f.flush
      sheet = Roo::Excelx.new(f.path)
      headers = sheet.row(1)
      (2..sheet.last_row.to_i).map { |i| headers.zip(sheet.row(i)).to_h }
    end
  end

  test "headers are identity columns only, no contact/guardian PII" do
    assert_equal(
      ["Student ID", "Name (EN)", "Name (TH)", "Program", "Degree",
       "Admission Year", "Graduation Year", "Status"],
      Exporters::StudentExporter::HEADERS
    )
  end

  test "filename and content type are xlsx" do
    exporter = Exporters::StudentExporter.new(relation)
    assert_equal "students.xlsx", exporter.filename
    assert_equal Exporters::Base::XLSX_CONTENT_TYPE, exporter.content_type
  end

  test "data dispatches to the xlsx binary" do
    exporter = Exporters::StudentExporter.new(relation)
    assert_equal exporter.to_xlsx, exporter.data
    assert_equal "PK", exporter.data[0, 2], "xlsx files are zip archives starting with PK"
  end

  test "student_id is written as text, not a number" do
    # An all-digit id rendered as a number would show in scientific notation in
    # Excel — the whole reason this export is xlsx rather than csv.
    student = students(:active_student)
    rows = parsed_rows(Exporters::StudentExporter.new(relation(Student.where(id: student.id))))
    cell = rows.first["Student ID"]

    assert_kind_of String, cell
    assert_equal student.student_id, cell
  end

  test "exports identity values including Thai name and titleized status" do
    student = students(:active_student)
    rows = parsed_rows(Exporters::StudentExporter.new(relation(Student.where(id: student.id))))
    row = rows.first

    assert_equal student.full_name, row["Name (EN)"]
    assert_equal student.full_name_th, row["Name (TH)"]
    assert_equal student.program.name_en, row["Program"]
    assert_equal student.program.degree_level.titleize, row["Degree"]
    assert_equal student.admission_year_be, row["Admission Year"]
    assert_equal "Active", row["Status"]
  end

  test "row count matches the given relation" do
    rel = relation(Student.where(status: "active"))
    rows = parsed_rows(Exporters::StudentExporter.new(rel))
    assert_equal rel.count, rows.size
  end
end
