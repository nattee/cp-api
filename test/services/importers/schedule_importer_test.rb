require "test_helper"

class Importers::ScheduleImporterTest < ActiveSupport::TestCase
  # --- attribute_definitions ---

  test "attribute_definitions returns all expected attributes" do
    defs = Importers::ScheduleImporter.attribute_definitions
    attrs = defs.map { |d| d[:attribute] }

    assert_includes attrs, :course_no
    assert_includes attrs, :section_number
    assert_includes attrs, :day
    assert_includes attrs, :start_time
    assert_includes attrs, :end_time
    assert_includes attrs, :building
    assert_includes attrs, :room_number
    assert_includes attrs, :instructor
    assert_includes attrs, :load_ratio
    assert_includes attrs, :semester_id
  end

  test "required_attributes includes course_no, section_number, day, start_time, end_time, semester_id" do
    required = Importers::ScheduleImporter.required_attributes
    assert_includes required, :course_no
    assert_includes required, :section_number
    assert_includes required, :day
    assert_includes required, :start_time
    assert_includes required, :end_time
    assert_includes required, :semester_id
  end

  test "semester_id has fixed_options" do
    defn = Importers::ScheduleImporter.attribute_definitions.find { |d| d[:attribute] == :semester_id }
    assert defn[:fixed_options].respond_to?(:call)
    options = defn[:fixed_options].call
    assert options.any?
    assert_equal 2, options.first.size # [label, value]
  end

  # --- auto_map ---

  test "auto_map matches English headers" do
    headers = %w[course_no section day start_time end_time building room_number instructor load_ratio]
    mapping = Importers::ScheduleImporter.auto_map(headers)

    assert_equal "A: course_no", mapping[:course_no]
    assert_equal "B: section", mapping[:section_number]
    assert_equal "C: day", mapping[:day]
    assert_equal "F: building", mapping[:building]
    assert_equal "H: instructor", mapping[:instructor]
  end

  test "auto_map matches Thai headers" do
    headers = %w[รหัสวิชา ตอน วัน เวลาเริ่ม เวลาสิ้นสุด อาคาร ห้อง อาจารย์]
    mapping = Importers::ScheduleImporter.auto_map(headers)

    assert_equal "A: รหัสวิชา", mapping[:course_no]
    assert_equal "B: ตอน", mapping[:section_number]
    assert_equal "C: วัน", mapping[:day]
    assert_equal "H: อาจารย์", mapping[:instructor]
  end

  # --- day parsing ---

  test "parse_day handles English full names" do
    importer = build_importer
    assert_equal 1, importer.send(:parse_day, "Monday")
    assert_equal 5, importer.send(:parse_day, "Friday")
  end

  test "parse_day handles English abbreviations" do
    importer = build_importer
    assert_equal 1, importer.send(:parse_day, "Mon")
    assert_equal 3, importer.send(:parse_day, "Wed")
  end

  test "parse_day handles two-letter abbreviations" do
    importer = build_importer
    assert_equal 1, importer.send(:parse_day, "MO")
    assert_equal 4, importer.send(:parse_day, "TH")
  end

  test "parse_day handles Thai day names" do
    importer = build_importer
    assert_equal 1, importer.send(:parse_day, "จันทร์")
    assert_equal 5, importer.send(:parse_day, "ศุกร์")
  end

  test "parse_day handles numeric values" do
    importer = build_importer
    assert_equal 0, importer.send(:parse_day, "0")
    assert_equal 6, importer.send(:parse_day, "6")
  end

  test "parse_day is case-insensitive" do
    importer = build_importer
    assert_equal 1, importer.send(:parse_day, "MONDAY")
    assert_equal 1, importer.send(:parse_day, "monday")
    assert_equal 1, importer.send(:parse_day, "mon")
  end

  test "parse_day returns nil for unknown values" do
    importer = build_importer
    assert_nil importer.send(:parse_day, "Funday")
  end

  # --- staff matching ---

  test "find_staff matches by display_name" do
    importer = build_importer
    smith = staffs(:lecturer_smith)
    # display_name = "ผศ.ดร. John Smith"
    staff = importer.send(:find_staff, smith.display_name)
    assert_equal smith, staff
  end

  test "find_staff matches by full_name" do
    importer = build_importer
    jones = staffs(:lecturer_jones)
    staff = importer.send(:find_staff, "Jane Jones")
    assert_equal jones, staff
  end

  test "find_staff matches by full_name_th" do
    importer = build_importer
    smith = staffs(:lecturer_smith)
    staff = importer.send(:find_staff, "จอห์น สมิธ")
    assert_equal smith, staff
  end

  test "find_staff matches by partial last_name" do
    importer = build_importer
    smith = staffs(:lecturer_smith)
    staff = importer.send(:find_staff, "Smith")
    assert_equal smith, staff
  end

  test "find_staff returns nil for unknown name" do
    importer = build_importer
    assert_nil importer.send(:find_staff, "Unknown Person")
  end

  # --- course lookup ---

  test "find_course finds by course_no with latest revision" do
    importer = build_importer
    course = importer.send(:find_course, "2110101", nil)
    assert_equal courses(:intro_computing), course
  end

  test "find_course finds by course_no with specific revision_year" do
    importer = build_importer
    course = importer.send(:find_course, "2110101", "2565")
    assert_equal courses(:intro_computing), course
  end

  test "find_course returns nil for unknown course" do
    importer = build_importer
    assert_nil importer.send(:find_course, "9999999", nil)
  end

  test "find_course auto-converts CE to BE" do
    importer = build_importer
    # 2022 CE → 2565 BE
    course = importer.send(:find_course, "2110101", "2022")
    assert_equal courses(:intro_computing), course
  end

  test "find_course strips Roo float suffix" do
    importer = build_importer
    course = importer.send(:find_course, "2110101.0", nil)
    assert_equal courses(:intro_computing), course
  end

  # --- full import via call ---

  test "call imports schedule CSV with find-or-create" do
    semester = semesters(:sem_2568_2)
    data_import = create_data_import("schedule_import.csv",
      column_mapping: {
        "course_no" => "A: course_no",
        "section_number" => "B: section",
        "day" => "C: day",
        "start_time" => "D: start_time",
        "end_time" => "E: end_time",
        "building" => "F: building",
        "room_number" => "G: room_number",
        "instructor" => "H: instructor",
        "load_ratio" => "I: load_ratio",
        "remark" => "J: remark"
      },
      default_values: { "semester_id" => semester.id.to_s }
    )

    Importers::ScheduleImporter.new(data_import).call
    data_import.reload

    assert_equal "completed", data_import.state
    assert_equal 4, data_import.total_rows

    # CourseOffering for intro_computing in sem_2568_2
    offering = CourseOffering.find_by(course: courses(:intro_computing), semester: semester)
    assert offering, "CourseOffering should be created"

    # Two sections (1 and 2)
    assert_equal 2, offering.sections.count
    sec1 = offering.sections.find_by(section_number: 1)
    sec2 = offering.sections.find_by(section_number: 2)
    assert sec1
    assert sec2

    # Section 1 has 2 time slots (Mon and Wed)
    assert_equal 2, sec1.time_slots.count
    # Section 2 has 1 time slot (Tue)
    assert_equal 1, sec2.time_slots.count

    # Section 2 remark
    assert_equal "Lab group", sec2.remark

    # Teaching: Smith teaches sec1
    assert_equal 1, sec1.teachings.count
    assert_equal staffs(:lecturer_smith), sec1.teachings.first.staff

    # Teaching: Jones teaches sec2 with 0.5 load
    jones_teaching = sec2.teachings.find_by(staff: staffs(:lecturer_jones))
    assert jones_teaching
    assert_in_delta 0.5, jones_teaching.load_ratio

    # Room created for ENG4-305
    room_305 = Room.find_by(building: "ENG4", room_number: "305")
    assert room_305, "Room ENG4-305 should be find-or-created"

    # CourseOffering for senior_project (row 4 — no room, no instructor)
    sp_offering = CourseOffering.find_by(course: courses(:senior_project), semester: semester)
    assert sp_offering
    sp_sec = sp_offering.sections.find_by(section_number: 1)
    assert sp_sec
    assert_equal 1, sp_sec.time_slots.count
    assert_nil sp_sec.time_slots.first.room
    assert_equal 0, sp_sec.teachings.count
  end

  test "call deduplicates on re-import" do
    semester = semesters(:sem_2568_2)
    mapping = {
      "course_no" => "A: course_no",
      "section_number" => "B: section",
      "day" => "C: day",
      "start_time" => "D: start_time",
      "end_time" => "E: end_time",
      "building" => "F: building",
      "room_number" => "G: room_number",
      "instructor" => "H: instructor",
      "load_ratio" => "I: load_ratio",
      "remark" => "J: remark"
    }
    defaults = { "semester_id" => semester.id.to_s }

    # First import
    di1 = create_data_import("schedule_import.csv", column_mapping: mapping, default_values: defaults)
    Importers::ScheduleImporter.new(di1).call

    # Count records after first import
    offering_count = CourseOffering.where(semester: semester).count
    section_count = Section.joins(:course_offering).where(course_offerings: { semester_id: semester.id }).count
    slot_count = TimeSlot.joins(section: :course_offering).where(course_offerings: { semester_id: semester.id }).count

    # Second import of same data
    di2 = create_data_import("schedule_import.csv", column_mapping: mapping, default_values: defaults)
    Importers::ScheduleImporter.new(di2).call
    di2.reload

    assert_equal "completed", di2.state

    # Counts should not change
    assert_equal offering_count, CourseOffering.where(semester: semester).count
    assert_equal section_count, Section.joins(:course_offering).where(course_offerings: { semester_id: semester.id }).count
    assert_equal slot_count, TimeSlot.joins(section: :course_offering).where(course_offerings: { semester_id: semester.id }).count
  end

  test "call fails for unknown course" do
    semester = semesters(:sem_2568_2)
    data_import = create_data_import("schedule_bad_course.csv",
      column_mapping: {
        "course_no" => "A: course_no",
        "section_number" => "B: section",
        "day" => "C: day",
        "start_time" => "D: start_time",
        "end_time" => "E: end_time"
      },
      default_values: { "semester_id" => semester.id.to_s }
    )

    Importers::ScheduleImporter.new(data_import).call
    data_import.reload

    assert_equal "failed", data_import.state
    assert_equal 1, data_import.error_count
    assert_match(/Course not found/, data_import.row_errors.first["errors"].first)
  end

  test "call reports unknown instructor as row error" do
    semester = semesters(:sem_2568_2)
    # Build a CSV with unknown instructor
    csv_content = "course_no,section,day,start_time,end_time,instructor\n2110101,1,Mon,09:00,10:30,Nobody Known\n"
    data_import = create_data_import_from_string(csv_content,
      column_mapping: {
        "course_no" => "A: course_no",
        "section_number" => "B: section",
        "day" => "C: day",
        "start_time" => "D: start_time",
        "end_time" => "E: end_time",
        "instructor" => "F: instructor"
      },
      default_values: { "semester_id" => semester.id.to_s }
    )

    Importers::ScheduleImporter.new(data_import).call
    data_import.reload

    assert_equal "failed", data_import.state
    assert_match(/Instructor not found/, data_import.row_errors.first["errors"].first)
  end

  test "call handles missing required fields" do
    data_import = create_data_import("schedule_import.csv",
      column_mapping: {
        "course_no" => "A: course_no"
        # missing other required fields
      }
    )

    Importers::ScheduleImporter.new(data_import).call
    data_import.reload

    assert_equal "failed", data_import.state
    assert_match(/Required fields not mapped/, data_import.error_message)
  end

  private

  def build_importer
    di = DataImport.new(target_type: "Schedule", mode: "upsert", state: "pending", user: users(:admin))
    Importers::ScheduleImporter.new(di)
  end

  def create_data_import(fixture_filename, column_mapping:, default_values: nil)
    di = DataImport.new(
      target_type: "Schedule",
      mode: "upsert",
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

  def create_data_import_from_string(csv_string, column_mapping:, default_values: nil)
    di = DataImport.new(
      target_type: "Schedule",
      mode: "upsert",
      state: "pending",
      user: users(:admin),
      column_mapping: column_mapping,
      default_values: default_values
    )
    di.file.attach(
      io: StringIO.new(csv_string),
      filename: "test.csv",
      content_type: "text/csv"
    )
    di.save!
    di
  end
end
