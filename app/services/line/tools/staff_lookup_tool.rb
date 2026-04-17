# Looks up staff/lecturers by name (Thai or English), initials, program, type, or status.
# Returns a JSON array of matching staff records.
class Line::Tools::StaffLookupTool
  DEFINITION = {
    description: "Look up staff or lecturer information. Search by name (Thai or English), initials (e.g. 'NNN'), " \
                 "and optionally filter by program, staff type, or status. " \
                 "Returns staff details including name, academic title, type, status, and affiliated programs.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Name (Thai or English) or initials (2-4 uppercase letters like 'NNN'). Optional if filters are provided."
        },
        program_code: {
          type: "string",
          description: "Program group code to filter by, e.g. 'CP', 'CEDT', 'CM', 'CS', 'SE', 'CD'"
        },
        staff_type: {
          type: "string",
          enum: Staff::STAFF_TYPES,
          description: "Staff type filter: lecturer, adjunct, lab, admin_permanent, admin_annual, or admin_short_term"
        },
        status: {
          type: "string",
          enum: Staff::STATUSES,
          description: "Status filter: active, retired, or on_leave"
        },
        count_only: {
          type: "boolean",
          description: "If true, return only the count of matching staff instead of full records. Use for 'how many' questions."
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
    staff_type = arguments["staff_type"].to_s.strip.presence
    status = arguments["status"].to_s.strip.presence
    count_only = arguments["count_only"] == true
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    scope = build_scope(query, program_code:, staff_type:, status:)

    if count_only
      { count: scope.count, filters: describe_filters(query, program_code, staff_type, status) }.to_json
    else
      total = scope.count
      staff = scope.limit(limit).map { |s| serialize(s) }
      result = { staff: staff, total: total }
      result[:note] = "Showing #{staff.size} of #{total} results" if total > staff.size
      result.to_json
    end
  end

  def self.build_scope(query, program_code:, staff_type:, status:)
    scope = Staff.left_joins(staff_programs: { program: :program_group }).distinct

    if query.present?
      if query.match?(/\A[A-Z]{2,4}\z/)
        # Looks like initials (2-4 uppercase letters)
        scope = scope.where(initials: query)
      else
        like = "%#{query}%"
        scope = scope.where(
          "staffs.first_name LIKE :q OR staffs.last_name LIKE :q OR " \
          "staffs.first_name_th LIKE :q OR staffs.last_name_th LIKE :q OR " \
          "staffs.academic_title LIKE :q",
          q: like
        )
      end
    end

    scope = scope.where(program_groups: { code: program_code.upcase }) if program_code
    scope = scope.where(staff_type: staff_type) if staff_type
    scope = scope.where(status: status) if status

    scope.order(:last_name, :first_name)
  end
  private_class_method :build_scope

  def self.serialize(staff_member)
    {
      name_th: staff_member.display_name_th,
      name_en: staff_member.display_name,
      initials: staff_member.initials,
      staff_type: staff_member.staff_type,
      status: staff_member.status,
      programs: staff_member.programs.includes(:program_group).map { |p|
        "#{p.program_group.code} (#{p.year_started})"
      }
    }
  end
  private_class_method :serialize

  def self.describe_filters(query, program_code, staff_type, status)
    parts = []
    parts << "query='#{query}'" if query.present?
    parts << "program=#{program_code}" if program_code
    parts << "staff_type=#{staff_type}" if staff_type
    parts << "status=#{status}" if status
    parts.join(", ")
  end
  private_class_method :describe_filters
end
