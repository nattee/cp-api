module Reports
  # Single source of truth for which reports exist and how the menu groups them.
  module Registry
    # Display order + labels for menu sections.
    SECTIONS = {
      courses:    "Courses",
      students:   "Students",
      curriculum: "Curriculum",
      thesis:     "Thesis",
      admin:      "Data"
    }.freeze

    # Add a new report here (one line) after creating its class file.
    REPORTS = [
      Reports::CourseTeachers,
      Reports::FailingStudents,
      Reports::SemesterGradeDistribution,
      Reports::CohortGpa,
      Reports::GroupCreditShortfall,
      Reports::ThesisCredits,
      Reports::StaffCoursesByYear,
      Reports::DataCoverage
    ].freeze

    def self.all
      REPORTS
    end

    def self.find(key)
      REPORTS.find { |r| r.key == key }
    end

    def self.for_program(program_group)
      REPORTS.select { |r| r.applicable_to?(program_group) }
    end

    # Groups by section in SECTIONS order; only sections that have reports appear.
    def self.grouped(reports = all)
      reports.group_by(&:section)
             .sort_by { |section, _| SECTIONS.keys.index(section) || Float::INFINITY }
             .to_h
    end
  end
end
