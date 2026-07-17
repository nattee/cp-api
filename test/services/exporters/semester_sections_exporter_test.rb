require "test_helper"
require "csv"

class Exporters::SemesterSectionsExporterTest < ActiveSupport::TestCase
  # Exports carry a UTF-8 BOM (Thai teacher names in Excel); strip it before
  # parsing or the first header comes back as "﻿course_no".
  def parse(exporter)
    CSV.parse(exporter.to_csv.delete_prefix(Exporters::Base::BOM), headers: true)
  end

  test "one row per section with expected headers" do
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)))

    # intro_computing_2568_1 has sections 1+2, senior_project_2568_1 has section 1
    assert_equal 3, csv.size
    assert_equal %w[course_no course_name section teachers schedule enrolled max status], csv.headers
  end

  test "section row carries teachers, schedule, and status" do
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)))
    row = csv.find { |r| r["course_no"] == "2110101" && r["section"] == "1" }

    assert_equal "JS", row["teachers"]
    assert_equal "Mon/Wed 09:00-10:30 ENG4-303", row["schedule"]
    assert_equal "confirmed", row["status"]
  end

  test "dept scope filters to 2110 courses; all includes everything" do
    dept = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2567_1), course_scope: "dept"))
    all = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2567_1), course_scope: "all"))

    assert_equal %w[2110101 2110101], dept["course_no"]
    assert_includes all["course_no"], "2103106"
    assert_equal 3, all.size
  end

  test "offering without sections emits one blank-section row" do
    CourseOffering.create!(course: courses(:gened_course), semester: semesters(:sem_2568_2), status: "planned")
    csv = parse(Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_2), course_scope: "all"))
    row = csv.find { |r| r["course_no"] == "2103106" }

    assert_nil row["section"]
    assert_equal "planned", row["status"]
  end

  test "filename carries the scope suffix" do
    assert_equal "sections_2568_1_dept.csv", Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1)).filename
    assert_equal "sections_2568_1.csv", Exporters::SemesterSectionsExporter.new(semesters(:sem_2568_1), course_scope: "all").filename
  end
end
