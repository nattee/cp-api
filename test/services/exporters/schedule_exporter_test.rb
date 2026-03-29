require "test_helper"
require "csv"

class Exporters::ScheduleExporterTest < ActiveSupport::TestCase
  test "headers match importer attribute names" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv)
    headers = csv.first

    assert_equal %w[course_no revision_year section_number day start_time end_time building room_number instructor load_ratio remark], headers
  end

  test "exports correct number of rows for time slots with teachers" do
    semester = semesters(:sem_2568_1)
    exporter = Exporters::ScheduleExporter.new(semester)
    csv = CSV.parse(exporter.to_csv, headers: true)

    # Fixture data for sem_2568_1:
    # intro_sec_1: 2 time slots (Mon, Wed), 1 teaching (smith) → 2 rows
    # intro_sec_2: 1 time slot (Tue), 2 teachings (jones, smith) → 2 rows
    # senior_sec_1: 0 time slots → 0 rows
    # Total: 4 rows
    assert_equal 4, csv.size
  end

  test "exports course and section data correctly" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv, headers: true)

    first_row = csv.find { |r| r["day"] == "Mon" }
    assert_equal "2110101", first_row["course_no"]
    assert_equal "2565", first_row["revision_year"]
    assert_equal "1", first_row["section_number"]
    assert_equal "Mon", first_row["day"]
    assert_equal "09:00", first_row["start_time"]
    assert_equal "10:30", first_row["end_time"]
  end

  test "exports room data" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv, headers: true)

    mon_row = csv.find { |r| r["day"] == "Mon" }
    assert_equal "ENG4", mon_row["building"]
    assert_equal "303", mon_row["room_number"]
  end

  test "exports instructor with display_name" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv, headers: true)

    mon_row = csv.find { |r| r["day"] == "Mon" }
    assert_equal staffs(:lecturer_smith).display_name, mon_row["instructor"]
    assert_equal "1.0", mon_row["load_ratio"]
  end

  test "multiple teachers produce multiple rows for same time slot" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv, headers: true)

    # Section 2, Tuesday — jones (0.5) and smith (0.5)
    tue_rows = csv.select { |r| r["day"] == "Tue" }
    assert_equal 2, tue_rows.size
    instructors = tue_rows.map { |r| r["instructor"] }.sort
    assert_includes instructors, staffs(:lecturer_jones).display_name
    assert_includes instructors, staffs(:lecturer_smith).display_name
  end

  test "time slot without teachers produces one row with blank instructor" do
    # Create a section with a time slot but no teachings
    offering = course_offerings(:senior_project_2568_1)
    section = sections(:senior_sec_1)
    TimeSlot.create!(section: section, day_of_week: 4, start_time: "09:00", end_time: "12:00")

    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    csv = CSV.parse(exporter.to_csv, headers: true)

    thu_rows = csv.select { |r| r["day"] == "Thu" }
    assert_equal 1, thu_rows.size
    assert_nil thu_rows.first["instructor"]
    assert_nil thu_rows.first["load_ratio"]
  end

  test "filename includes semester info" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_1))
    assert_equal "schedule_2568_1.csv", exporter.filename
  end

  test "empty semester produces CSV with only headers" do
    exporter = Exporters::ScheduleExporter.new(semesters(:sem_2568_2))
    csv = CSV.parse(exporter.to_csv, headers: true)
    assert_equal 0, csv.size
  end
end
