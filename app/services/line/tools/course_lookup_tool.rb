# Looks up courses by course number, name (Thai or English), program, or revision year.
# Returns a JSON array of matching course records.
#
# Note: the same course (same course_no) can exist as multiple rows with different
# revision_year_be values. Results are ordered newest revision first.
class Line::Tools::CourseLookupTool
  DEFINITION = {
    description: "Look up course information. Search by course number (e.g. '2110327'), name (Thai or English), " \
                 "and optionally filter by program or revision year. " \
                 "Returns course details including course_no, name (TH/EN), credits, revision year, and program.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Course number (e.g. '2110327') or part of a course name (Thai or English). Optional if filters are provided."
        },
        program_code: {
          type: "string",
          description: "Program group code to filter by, e.g. 'CP', 'CEDT', 'CM', 'CS', 'SE', 'CD'"
        },
        revision_year: {
          type: "integer",
          description: "Curriculum revision year in Buddhist Era (e.g. 2566). Filters courses by revision_year."
        },
        count_only: {
          type: "boolean",
          description: "If true, return only the count of matching courses instead of full records. Use for 'how many' questions."
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

  def self.call(arguments, user: nil)
    query = arguments["query"].to_s.strip
    program_code = arguments["program_code"].to_s.strip.presence
    revision_year = arguments["revision_year"]
    count_only = arguments["count_only"] == true
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    scope = build_scope(query, program_code:, revision_year:)

    if count_only
      { count: scope.count, filters: describe_filters(query, program_code, revision_year) }.to_json
    else
      total = scope.count
      courses = scope.limit(limit).map { |c| serialize(c) }
      result = { courses: courses, total: total }
      result[:note] = "Showing #{courses.size} of #{total} results" if total > courses.size
      result.to_json
    end
  end

  def self.build_scope(query, program_code:, revision_year:)
    scope = Course.left_joins(program_courses: { program: :program_group }).distinct

    if query.present?
      if query.match?(/\A\d+\z/)
        scope = scope.where("courses.course_no LIKE ?", "#{query}%")
      else
        like = "%#{query}%"
        scope = scope.where(
          "courses.name LIKE :q OR courses.name_th LIKE :q OR courses.name_abbr LIKE :q",
          q: like
        )
      end
    end

    scope = scope.where(program_groups: { code: program_code.upcase }) if program_code
    scope = scope.where(revision_year_be: revision_year) if revision_year

    scope.order(course_no: :asc, revision_year_be: :desc)
  end
  private_class_method :build_scope

  def self.serialize(course)
    prog = course.programs.first
    {
      course_no: course.course_no,
      name_en: course.name,
      name_th: course.name_th,
      credits: course.credits,
      revision_year: course.revision_year_be,
      program: prog ? "#{prog.program_group.code} (#{prog.year_started_be})" : nil,
      is_gened: course.is_gened,
      is_thesis: course.is_thesis
    }
  end
  private_class_method :serialize

  def self.describe_filters(query, program_code, revision_year)
    parts = []
    parts << "query='#{query}'" if query.present?
    parts << "program=#{program_code}" if program_code
    parts << "revision_year=#{revision_year}" if revision_year
    parts.join(", ")
  end
  private_class_method :describe_filters
end
