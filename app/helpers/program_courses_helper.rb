module ProgramCoursesHelper
  # Courses not yet linked to this program, for the "Add Course" dropdown.
  def available_courses(program)
    Course.where.not(id: program.course_ids).order(:course_no, revision_year_be: :desc)
  end

  # Datalist suggestions for the group-code field: codes already used by this
  # program + label-constant keys carrying this program's prefix.
  def group_code_suggestions(program)
    used = program.program_courses.where.not(course_group_code: [nil, ""])
                  .distinct.pluck(:course_group_code)
    known = ProgramCourse::COURSE_GROUP_LABELS.keys
                                              .select { |k| k.start_with?("#{program.program_code}-") }
    (used + known).uniq.sort
  end
end
