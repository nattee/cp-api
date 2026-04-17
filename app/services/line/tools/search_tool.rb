# Cross-entity search across students, staff, and courses.
# Used when the user sends a short or ambiguous query (e.g. just a name)
# and we need to figure out what entity type they mean.
class Line::Tools::SearchTool
  DEFINITION = {
    description: "Search across students, staff, and courses simultaneously. " \
                 "Use this when the user sends a short or ambiguous message (a name, ID, or course number) " \
                 "and you're not sure whether they mean a student, lecturer, or course. " \
                 "Returns matches from all entity types so you can ask for clarification or respond directly.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "A name (Thai or English), student ID, staff initials, or course number to search across all entities."
        },
        limit: {
          type: "integer",
          description: "Max results per entity type (default 3, max 10)"
        }
      },
      required: [ "query" ]
    }
  }.freeze

  MAX_LIMIT = 10
  DEFAULT_LIMIT = 3

  def self.call(arguments)
    query = arguments["query"].to_s.strip
    return { error: "query is required" }.to_json if query.blank?

    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    students = search_students(query, limit)
    staff = search_staff(query, limit)
    courses = search_courses(query, limit)

    {
      students: students[:results],
      students_total: students[:total],
      staff: staff[:results],
      staff_total: staff[:total],
      courses: courses[:results],
      courses_total: courses[:total],
      summary: "Found #{students[:total]} student(s), #{staff[:total]} staff, #{courses[:total]} course(s) matching '#{query}'"
    }.to_json
  end

  # --- Student search ---

  def self.search_students(query, limit)
    scope = Student.joins(program: :program_group)

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

    total = scope.count
    results = scope.order(:student_id).limit(limit).map do |s|
      {
        student_id: s.student_id,
        name_th: s.full_name_th,
        name_en: s.full_name,
        program: "#{s.program.program_group.code} (#{s.program.year_started})",
        status: s.status
      }
    end

    { results: results, total: total }
  end
  private_class_method :search_students

  # --- Staff search ---

  def self.search_staff(query, limit)
    scope = Staff.all

    if query.match?(/\A[A-Z]{2,4}\z/)
      scope = scope.where(initials: query)
    else
      like = "%#{query}%"
      scope = scope.where(
        "staffs.first_name LIKE :q OR staffs.last_name LIKE :q OR " \
        "staffs.first_name_th LIKE :q OR staffs.last_name_th LIKE :q",
        q: like
      )
    end

    total = scope.count
    results = scope.order(:last_name, :first_name).limit(limit).map do |s|
      {
        name_th: s.display_name_th,
        name_en: s.display_name,
        initials: s.initials,
        staff_type: s.staff_type,
        status: s.status
      }
    end

    { results: results, total: total }
  end
  private_class_method :search_staff

  # --- Course search ---

  def self.search_courses(query, limit)
    scope = Course.where(auto_generated: "none")

    if query.match?(/\A\d+\z/)
      scope = scope.where("courses.course_no LIKE ?", "#{query}%")
    else
      like = "%#{query}%"
      scope = scope.where(
        "courses.course_no LIKE :q OR courses.name LIKE :q",
        q: like
      )
    end

    # Deduplicate across revision years — show the latest revision only
    scope = scope.order(revision_year: :desc)
    total_unique = scope.select("DISTINCT course_no").count
    results = []
    seen = Set.new

    scope.each do |c|
      break if results.size >= limit
      next if seen.include?(c.course_no)
      seen.add(c.course_no)
      results << {
        course_no: c.course_no,
        name: c.name,
        credits: c.credits,
        revision_year: c.revision_year
      }
    end

    { results: results, total: total_unique }
  end
  private_class_method :search_courses
end
