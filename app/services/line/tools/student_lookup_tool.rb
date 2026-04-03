# Looks up students by ID, name (Thai or English), program, year, or status.
# Returns a JSON array of matching student records.
class Line::Tools::StudentLookupTool
  DEFINITION = {
    description: "Look up student information. Search by student ID, name (Thai or English), " \
                 "and optionally filter by program, admission year, or status. " \
                 "Returns student details including name, program, status, admission year, and GPA.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Student ID (e.g. '6530200321') or part of a name (Thai or English). Optional if filters are provided."
        },
        program_code: {
          type: "string",
          description: "Program group code to filter by, e.g. 'CP', 'CEDT', 'CM', 'CS', 'SE', 'CD'"
        },
        admission_year: {
          type: "integer",
          description: "Admission year in Buddhist Era (e.g. 2568). Filters students by admission_year_be."
        },
        status: {
          type: "string",
          enum: Student::STATUSES,
          description: "Student status filter: active, graduated, on_leave, or retired"
        },
        count_only: {
          type: "boolean",
          description: "If true, return only the count of matching students instead of full records. Use for 'how many' questions."
        },
        limit: {
          type: "integer",
          description: "Max number of results to return (default 10, max 50)"
        }
      },
      required: []
    }
  }.freeze

  MAX_LIMIT = 50
  DEFAULT_LIMIT = 10

  def self.call(arguments)
    query = arguments["query"].to_s.strip
    program_code = arguments["program_code"].to_s.strip.presence
    admission_year = arguments["admission_year"]
    status = arguments["status"].to_s.strip.presence
    count_only = arguments["count_only"] == true
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    scope = build_scope(query, program_code:, admission_year:, status:)

    if count_only
      { count: scope.count, filters: describe_filters(query, program_code, admission_year, status) }.to_json
    else
      total = scope.count
      students = scope.limit(limit).map { |s| serialize(s) }
      result = { students: students, total: total }
      result[:note] = "Showing #{students.size} of #{total} results" if total > students.size
      result.to_json
    end
  end

  def self.build_scope(query, program_code:, admission_year:, status:)
    scope = Student.joins(program: :program_group)

    if query.present?
      if query.match?(/\A\d+\z/)
        scope = scope.where("students.student_id LIKE ?", "#{query}%")
      else
        like = "%#{query}%"
        scope = scope.where(
          "students.first_name LIKE :q OR students.last_name LIKE :q OR " \
          "students.first_name_th LIKE :q OR students.last_name_th LIKE :q",
          q: like
        )
      end
    end

    scope = scope.where(program_groups: { code: program_code.upcase }) if program_code
    scope = scope.where(admission_year_be: admission_year) if admission_year
    scope = scope.where(status: status) if status

    scope.order(:student_id)
  end
  private_class_method :build_scope

  def self.serialize(student)
    {
      student_id: student.student_id,
      name_th: student.full_name_th,
      name_en: student.full_name,
      program: "#{student.program.program_group.code} (#{student.program.year_started})",
      status: student.status,
      admission_year: student.admission_year_be,
      gpa: student.gpa,
      total_credits: student.total_credits
    }
  end
  private_class_method :serialize

  def self.describe_filters(query, program_code, admission_year, status)
    parts = []
    parts << "query='#{query}'" if query.present?
    parts << "program=#{program_code}" if program_code
    parts << "admission_year=#{admission_year}" if admission_year
    parts << "status=#{status}" if status
    parts.join(", ")
  end
  private_class_method :describe_filters
end
