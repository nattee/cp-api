# Shared resolution of the optional 'YEAR/NUMBER' (B.E.) semester parameter
# used by LINE tools that default to the latest semester. Returns a Semester
# on success, or an { error: } hash the caller returns as JSON:
#
#   semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
#   return semester.to_json unless semester.is_a?(Semester)
#
# (course_offering_lookup keeps its own parser: for it, a blank semester
# means "all semesters", not "the latest".)
module Line::Tools::SemesterParam
  module_function

  def resolve(str)
    str = str.to_s.strip
    if str.blank?
      return Semester.ordered.first || { error: "No semesters in the system yet." }
    end

    year, num = str.split("/")
    unless year.to_i.positive? && num.to_i.positive?
      return { error: "Could not parse semester '#{str}'. Use 'YEAR/NUMBER', e.g. '2568/1'." }
    end

    Semester.find_by(year_be: year.to_i, semester_number: num.to_i) ||
      { error: "No semester #{str} in the system." }
  end
end
