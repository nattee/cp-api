module Exporters
  # Human-facing listing of a semester's offerings, one row per section
  # (plus one blank-section row per offering that has no sections, so the
  # export is always a complete offering list). Unlike ScheduleExporter this
  # does NOT round-trip through an importer — it mirrors the semesters/show
  # table, including its course_scope filter.
  class SemesterSectionsExporter < Base
    include CourseOfferingsHelper

    HEADERS = %w[course_no course_name section teachers schedule enrolled max status].freeze

    attr_reader :semester, :course_scope

    def initialize(semester, course_scope: "dept")
      @semester = semester
      @course_scope = course_scope
    end

    def filename
      suffix = course_scope == "dept" ? "_dept" : ""
      "sections_#{semester.year_be}_#{semester.semester_number}#{suffix}.csv"
    end

    private

    # Teacher names fall back to Thai; BOM makes Excel read the file as UTF-8.
    # Safe here because this CSV never feeds an importer.
    def byte_order_mark?
      true
    end

    def rows
      offerings = semester.course_offerings.joins(:course)
      offerings = offerings.where("courses.course_no LIKE ?", "2110%") if course_scope == "dept"
      offerings = offerings.order("courses.course_no")
                           .includes(:course, sections: [{ teachings: :staff }, { time_slots: :room }])

      offerings.flat_map do |offering|
        course = offering.course
        if offering.sections.any?
          offering.sections.sort_by(&:section_number).map do |section|
            [course.course_no, course.name, section.section_number,
             section.teachings.map { |t| staff_short_name(t.staff) }.join(", "),
             section_schedule_summary(section),
             section.enrollment_current, section.enrollment_max,
             offering.status]
          end
        else
          [[course.course_no, course.name, nil, nil, nil, nil, nil, offering.status]]
        end
      end
    end
  end
end
