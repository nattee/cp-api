require "test_helper"

class Importers::StudentImporterTest < ActiveSupport::TestCase
  # --- attribute_definitions ---

  test "attribute_definitions returns all expected attributes" do
    defs = Importers::StudentImporter.attribute_definitions
    attrs = defs.map { |d| d[:attribute] }

    assert_includes attrs, :student_id
    assert_includes attrs, :first_name
    assert_includes attrs, :last_name
    assert_includes attrs, :admission_year_be
    assert_includes attrs, :program_name
  end

  test "required_attributes includes student_id, first_name, last_name, admission_year_be" do
    required = Importers::StudentImporter.required_attributes
    assert_equal [:student_id, :first_name, :last_name, :admission_year_be], required
  end

  # --- auto_map ---

  test "auto_map matches English headers with column letter prefix" do
    headers = ["student_id", "first_name", "last_name", "admission_year_be", "email"]
    mapping = Importers::StudentImporter.auto_map(headers)

    assert_equal "A: student_id", mapping[:student_id]
    assert_equal "B: first_name", mapping[:first_name]
    assert_equal "C: last_name", mapping[:last_name]
    assert_equal "D: admission_year_be", mapping[:admission_year_be]
    assert_equal "E: email", mapping[:email]
  end

  test "auto_map matches Thai headers with column letter prefix" do
    headers = ["รหัสนิสิต", "ชื่อ", "นามสกุล", "ปีที่รับเข้า"]
    mapping = Importers::StudentImporter.auto_map(headers)

    assert_equal "A: รหัสนิสิต", mapping[:student_id]
    assert_equal "B: ชื่อ", mapping[:first_name]
    assert_equal "C: นามสกุล", mapping[:last_name]
    assert_equal "D: ปีที่รับเข้า", mapping[:admission_year_be]
  end

  test "auto_map is case-insensitive" do
    headers = ["Student_ID", "First_Name", "Last_Name", "Admission_Year"]
    mapping = Importers::StudentImporter.auto_map(headers)

    assert_equal "A: Student_ID", mapping[:student_id]
    assert_equal "B: First_Name", mapping[:first_name]
  end

  test "auto_map skips unrecognized headers" do
    headers = ["student_id", "unknown_column", "first_name", "last_name", "admission_year_be"]
    mapping = Importers::StudentImporter.auto_map(headers)

    assert_nil mapping[:unknown_column]
    assert_equal 4, mapping.size
  end

  test "auto_map does not double-claim headers" do
    # "ชื่อ" is an alias for first_name — it should not also map to first_name_th
    headers = ["รหัสนิสิต", "ชื่อ", "นามสกุล", "ปีที่รับเข้า"]
    mapping = Importers::StudentImporter.auto_map(headers)

    assert_equal "B: ชื่อ", mapping[:first_name]
    assert_nil mapping[:first_name_th]
  end

  # --- resolve_program (via transform_attributes) ---

  test "resolve_program finds by program_code" do
    program = programs(:cp_bachelor)
    importer = build_importer

    attrs = { program_name: program.program_code, student_id: "1", admission_year_be: 2567, status: "active" }
    result = importer.send(:transform_attributes, attrs)

    assert_equal program.id, result[:program_id]
  end

  test "resolve_program finds by English name" do
    program = programs(:cp_bachelor)
    importer = build_importer

    attrs = { program_name: "Computer Engineering (Bachelor)", student_id: "1", admission_year_be: 2567, status: "active" }
    result = importer.send(:transform_attributes, attrs)

    assert_equal program.id, result[:program_id]
  end

  test "resolve_program finds by Thai name" do
    program = programs(:cp_bachelor)
    importer = build_importer

    attrs = { program_name: "วิศวกรรมคอมพิวเตอร์ (ปริญญาตรี)", student_id: "1", admission_year_be: 2567, status: "active" }
    result = importer.send(:transform_attributes, attrs)

    assert_equal program.id, result[:program_id]
  end

  test "resolve_program returns nil for unmatched name" do
    importer = build_importer

    attrs = { program_name: "Nonexistent Program", student_id: "1", admission_year_be: 2567, status: "active" }
    result = importer.send(:transform_attributes, attrs)

    assert_nil result[:program_id]
  end

  test "resolve_program prefers latest year_started when names match" do
    # Create a newer program with the same English name
    older = programs(:cp_bachelor) # year_started: 2540
    newer = Program.create!(
      program_code: "9999",
      name_en: older.name_en,
      name_th: "วิศวกรรมคอมพิวเตอร์ (ปริญญาตรี) ฉบับใหม่",
      degree_level: "bachelor",
      degree_name: "Bachelor of Engineering",
      field_of_study: "Computer Engineering",
      year_started: 2560
    )
    importer = build_importer

    attrs = { program_name: older.name_en, student_id: "1", admission_year_be: 2567, status: "active" }
    result = importer.send(:transform_attributes, attrs)

    assert_equal newer.id, result[:program_id]
  end

  # --- full import via call ---

  test "call imports CSV with column_mapping" do
    # CSV headers: student_id,first_name,last_name,admission_year_be,status,program
    data_import = create_data_import("students_import.csv",
      column_mapping: {
        "student_id" => "A: student_id",
        "first_name" => "B: first_name",
        "last_name" => "C: last_name",
        "admission_year_be" => "D: admission_year_be",
        "status" => "E: status",
        "program_name" => "F: program"
      }
    )

    Importers::StudentImporter.new(data_import).call
    data_import.reload

    assert_equal "completed", data_import.state
    assert_equal 2, data_import.created_count
    assert_equal 0, data_import.error_count
    assert Student.find_by(student_id: "9900100001")
    assert Student.find_by(student_id: "9900100002")
  end

  test "call applies default_values as constants" do
    # CSV headers: student_id,first_name,last_name,admission_year_be
    data_import = create_data_import("students_minimal.csv",
      column_mapping: {
        "student_id" => "A: student_id",
        "first_name" => "B: first_name",
        "last_name" => "C: last_name",
        "admission_year_be" => "D: admission_year_be"
      },
      default_values: {
        "status" => "on_leave",
        "program_name" => programs(:cp_bachelor).program_code
      }
    )

    Importers::StudentImporter.new(data_import).call
    data_import.reload

    assert_equal "completed", data_import.state
    student = Student.find_by(student_id: "9900300001")
    assert_equal "on_leave", student.status
    assert_equal programs(:cp_bachelor).id, student.program_id
  end

  test "call with Thai headers via column_mapping" do
    # CSV headers: รหัสนิสิต,ชื่อ,นามสกุล,ปีที่รับเข้า,สถานะ
    data_import = create_data_import("students_thai_headers.csv",
      column_mapping: {
        "student_id" => "A: รหัสนิสิต",
        "first_name" => "B: ชื่อ",
        "last_name" => "C: นามสกุล",
        "admission_year_be" => "D: ปีที่รับเข้า",
        "status" => "E: สถานะ"
      },
      default_values: { "program_name" => programs(:cp_bachelor).program_code }
    )

    Importers::StudentImporter.new(data_import).call
    data_import.reload

    assert_equal "completed", data_import.state
    student = Student.find_by(student_id: "9900200001")
    assert_equal "วิชัย", student.first_name
  end

  test "call fails when required column missing from mapping" do
    data_import = create_data_import("students_import.csv",
      column_mapping: {
        "student_id" => "A: student_id",
        "first_name" => "B: first_name"
        # missing last_name and admission_year_be
      }
    )

    Importers::StudentImporter.new(data_import).call
    data_import.reload

    assert_equal "failed", data_import.state
    assert_match(/Required fields not mapped/, data_import.error_message)
  end

  private

  def build_importer
    di = DataImport.new(target_type: "Student", mode: "create_only", state: "pending", user: users(:admin))
    Importers::StudentImporter.new(di)
  end

  def create_data_import(fixture_filename, column_mapping:, default_values: nil)
    di = DataImport.new(
      target_type: "Student",
      mode: "create_only",
      state: "pending",
      user: users(:admin),
      column_mapping: column_mapping,
      default_values: default_values
    )
    di.file.attach(
      io: File.open(Rails.root.join("test/fixtures/files", fixture_filename)),
      filename: fixture_filename,
      content_type: "text/csv"
    )
    di.save!
    di
  end
end
