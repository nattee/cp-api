module DataProvenance
  # Live numbers for /data_sources/provenance: which door each table's rows came
  # through. Narrative (timeline, gaps) lives in the view; see docs/data-provenance-report.md.
  class Summary
    def students_by_source
      @students_by_source ||= Student.group(:source).count
    end

    def grades_by_source
      @grades_by_source ||= Grade.group(:source).count
    end

    def courses_by_generation
      @courses_by_generation ||= Course.group(:auto_generated).count
    end

    def counts
      @counts ||= {
        program_groups: ProgramGroup.count, programs: Program.count, program_courses: ProgramCourse.count,
        staffs: Staff.count, semesters: Semester.count, course_offerings: CourseOffering.count,
        sections: Section.count, time_slots: TimeSlot.count, teachings: Teaching.count, rooms: Room.count,
        advisorships: Advisorship.count, users: User.count, roles: Role.count
      }
    end

    def imports
      @imports ||= DataImport.includes(:user, file_attachment: :blob).order(:id).to_a
    end

    def scrapes
      @scrapes ||= Scrape.includes(:semester).order(:id).to_a
    end

    def book
      @book ||= { lines: Book30Entry.count, placeholders: Student.where(source: "book30").count }
    end

    def students_with_grades
      @students_with_grades ||= Grade.distinct.count(:student_id)
    end

    def grade_year_range
      @grade_year_range ||= [ Grade.minimum(:year_ce), Grade.maximum(:year_ce) ]
    end
  end
end
