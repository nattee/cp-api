module Reports
  # Single source of truth for every report the app exposes and how the hub +
  # sidebar present them. Section assignment and card copy live HERE (the
  # presentation layer), not on the report classes — a report's analytical
  # identity is separate from which hub drawer it sits in, and external reports
  # have no report class to hold that metadata. Registry reports render through
  # ReportsController#show; external reports render in their own controllers and
  # are listed here only for navigation.
  module Catalog
    # Display order + labels. :system is never shown in the hub.
    SECTIONS = {
      schedules: "Schedules",
      teaching:  "Teaching",
      grades:    "Grades & Courses",
      students:  "Students & Cohorts",
      system:    "System"
    }.freeze

    module_function

    def entries
      [
        # --- Schedules (timetables + the "is my timetable broken?" check) ---
        external("schedules_room",            "Room Schedule",        "Room usage across the week for a semester",        :schedules, :schedules_room_path,       access: "courses.read"),
        external("schedules_staff",           "Staff Schedule",       "A lecturer's weekly timetable and load",           :schedules, :schedules_staff_path,      access: "courses.read"),
        external("schedules_student",         "Student Timetable",    "A student's weekly schedule with grades",          :schedules, :schedules_student_path,    access: "grades.read"),
        external("schedules_curriculum",      "Curriculum Calendar",  "Combined weekly calendar for a set of courses",    :schedules, :schedules_curriculum_path, access: "courses.read"),
        external("schedules_conflicts",       "Conflict Detection",   "Room and staff double-bookings for a semester",    :schedules, :schedules_conflicts_path,  access: "courses.read"),
        # --- Teaching (teaching analytics: matrices + per-lecturer year) ---
        external("schedules_workload",        "Staff Workload",       "Teaching load per lecturer across semesters",      :teaching, :schedules_workload_path,        access: "courses.read"),
        external("schedules_teaching_matrix", "Teaching Matrix",      "Sections taught per lecturer per course",          :teaching, :schedules_teaching_matrix_path, access: "courses.read"),
        registry(Reports::StaffCoursesByYear, "Courses and co-lecturers a lecturer taught in a year, with seats", :teaching, access: "courses.read"),
        # --- Grades & Courses ---
        registry(Reports::SemesterGradeDistribution, "Per-course grade counts and GPA for a program and term", :grades, access: "grades.read"),
        external("grades_distribution",       "Class Grade Distribution", "Grade spread and pass rate per subject across terms", :grades, :distribution_grades_path, access: "grades.read"),
        registry(Reports::FailingStudents,    "Students who received F in a course and term", :grades, access: "grades.read"),
        # --- Students & Cohorts ---
        registry(Reports::CohortGpa,          "Per-term GPA and GPAX for one admission cohort", :students, access: "grades.read"),
        registry(Reports::GroupCreditShortfall, "Students below a credit threshold in a course group", :students, access: "grades.read"),
        registry(Reports::ThesisCredits,      "Enrolled thesis credits per student (master programs)", :students, access: "grades.read"),
        # --- System (admin operational check; not shown in the hub) ---
        registry(Reports::DataCoverage,       "Per-term data-coverage matrix with gaps flagged", :system, access: "users.manage")
      ]
    end

    # Hub list, filtered to what this user may open.
    def hub_entries(user:)
      entries.select { |e| e.hub? && user.can?(e.access) }
    end

    def find(key)
      entries.find { |e| e.key == key }
    end

    # Groups by section in SECTIONS order; only sections present appear.
    def grouped(list)
      list.group_by(&:section)
          .sort_by { |section, _| SECTIONS.keys.index(section) || Float::INFINITY }
          .to_h
    end

    def external(key, title, description, section, path_helper, access:)
      CatalogEntry.new(key: key, title: title, description: description,
                       section: section, access: access, path_helper: path_helper,
                       report_class: nil)
    end

    def registry(klass, description, section, access:)
      CatalogEntry.new(key: klass.key, title: klass.title, description: description,
                       section: section, access: access, path_helper: nil,
                       report_class: klass)
    end

    # entries/hub_entries/find/grouped are the public API; external/registry are
    # just internal builders for the entries list.
    private_class_method :external, :registry
  end
end
