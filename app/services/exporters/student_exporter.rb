module Exporters
  # Exports a (typically filtered) collection of students to XLSX. Columns are
  # plain values — unlike the datatable JSON, which renders HTML badges/partials,
  # the export emits raw data. Intentionally excludes contact/guardian PII;
  # this list is admin-gated but kept to identity/enrollment data.
  class StudentExporter < Base
    HEADERS = [
      "Student ID", "Name (EN)", "Name (TH)", "Program", "Degree",
      "Admission Year", "Graduation Year", "Status"
    ].freeze

    # student_id is an all-digit string — force :string so Excel doesn't render
    # it in scientific notation. Years auto-infer as integers; the rest as text.
    COLUMN_TYPES = [:string, nil, nil, nil, nil, nil, nil, nil].freeze

    # `students` is an ActiveRecord relation. Pass one that already eager-loads
    # `program: :program_group` to avoid N+1 across the full result set.
    def initialize(students)
      @students = students
    end

    def filename
      "students.xlsx"
    end

    private

    def xlsx?
      true
    end

    def worksheet_name
      "Students"
    end

    def column_types
      COLUMN_TYPES
    end

    def rows
      @students.map do |student|
        [
          student.student_id,
          student.full_name,
          student.full_name_th,
          student.program&.name_en,
          student.program&.degree_level&.titleize,
          student.admission_year_be,
          student.graduation_year_be,
          student.status&.titleize
        ]
      end
    end
  end
end
