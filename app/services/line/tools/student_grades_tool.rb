# Per-term academic record for ONE student: courses + grades per semester,
# term GPA, and cumulative GPAX. The LINE-shaped version of the student show
# page's course history. Chula transcript naming: GPA = semester, GPAX =
# cumulative.
class Line::Tools::StudentGradesTool
  DEFINITION = {
    description: "Get one student's academic record term by term: the courses they took with grades, " \
                 "the semester GPA, and the cumulative GPAX (Chula convention: GPA = semester, " \
                 "GPAX = cumulative; term labels are Buddhist Era like '2567/1'). " \
                 "Use for questions like 'how did student X perform?', 'grades of 6530200321', " \
                 "'is X improving?', or 'did X take course Y?'. Search by student ID or name. " \
                 "For a student's profile without grades use student_lookup instead.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Student ID (e.g. '6530200321') or part of a name (Thai or English). Required."
        },
        semester: {
          type: "string",
          description: "Term in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2567/2'. Omit for all terms."
        }
      },
      required: [ "query" ]
    }
  }.freeze

  MAX_MATCH_CHOICES = 5

  def self.call(arguments, user: nil)
    query = arguments["query"].to_s.strip
    return { error: "query is required" }.to_json if query.blank?

    students = find_students(query)
    return { error: "No student found matching '#{query}'" }.to_json if students.empty?

    if students.size > 1
      return {
        error: "Multiple students match '#{query}'. Ask which one is meant, then retry with the student ID.",
        matches: students.first(MAX_MATCH_CHOICES).map { |s|
          { student_id: s.student_id, name: s.display_name,
            program: s.program.program_group.code, admission_year_be: s.admission_year_be }
        }
      }.to_json
    end

    student = students.first
    terms = GradeStats::StudentTranscript.call(student: student)[:terms]

    if (semester_str = arguments["semester"].to_s.strip.presence)
      year_be, num = parse_term(semester_str)
      return { error: "Could not parse semester '#{semester_str}'. Use 'YEAR/NUMBER', e.g. '2567/2'." }.to_json unless year_be

      terms = terms.select { |t| t[:year_ce] + 543 == year_be && t[:semester] == num }
    end

    {
      student: {
        student_id: student.student_id,
        name: student.display_name,
        program: student.program.program_group.code,
        admission_year_be: student.admission_year_be,
        status: student.status
      },
      terms: terms.map { |t|
        { term: "#{t[:year_ce] + 543}/#{t[:semester]}",
          courses: t[:courses], gpa: t[:gpa], gpax: t[:gpax] }
      },
      gpax: student.gpa&.to_f,
      total_credits: student.total_credits
    }.to_json
  end

  def self.find_students(query)
    scope = Student.includes(program: :program_group)
    if query.match?(/\A\d+\z/)
      scope.where("student_id LIKE ?", "#{query}%").order(:student_id).to_a
    else
      like = "%#{query}%"
      scope.where(
        "first_name LIKE :q OR last_name LIKE :q OR " \
        "first_name_th LIKE :q OR last_name_th LIKE :q OR " \
        "CONCAT(first_name, ' ', last_name) LIKE :q OR " \
        "CONCAT(first_name_th, ' ', last_name_th) LIKE :q",
        q: like
      ).order(:student_id).to_a
    end
  end
  private_class_method :find_students

  # "2567/2" → [2567, 2]; nil on anything unparseable.
  def self.parse_term(str)
    year, num = str.split("/")
    return nil unless year.to_i.positive? && num.to_i.positive?

    [ year.to_i, num.to_i ]
  end
  private_class_method :parse_term
end
