# Looks up staff/lecturers by name (Thai or English), initials, program, type, or status.
# Returns a JSON array of matching staff records.
class Line::Tools::StaffLookupTool
  DEFINITION = {
    description: "Look up staff or lecturer information. Search by name (Thai or English), initials (e.g. 'NNN'), " \
                 "and optionally filter by program, staff type, or status. " \
                 "Returns staff details including name, academic title, type, status, and affiliated programs. " \
                 "Also returns recent teaching assignments per semester with section counts and total " \
                 "teaching load — use this for 'what does X teach?' and 'how much does X teach?'. " \
                 "Counts and lists include RETIRED staff unless you pass status — for 'how many lecturers " \
                 "do we have' or 'who are our lecturers' (current staff) pass status='active'. Every result " \
                 "carries a by_status breakdown; lists are ordered active staff first.",
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
  RECENT_TERMS = 3

  # List order: current staff before former. Alphabetical-only ordering let the
  # MAX_LIMIT cut drop ACTIVE lecturers while keeping retired ones (prod
  # 2026-09-12: Sudsang was 55th of 74 by surname, past the 50-row cap, while
  # 21 retired staff made the list and were presented as "active lecturers").
  STATUS_ORDER = %w[active on_leave retired].freeze
  STATUS_ORDER_SQL = Arel.sql(
    "FIELD(staffs.status, #{STATUS_ORDER.map { |st| "'#{st}'" }.join(", ")})"
  )

  def self.call(arguments, user: nil)
    query = arguments["query"].to_s.strip
    program_code = arguments["program_code"].to_s.strip.presence
    staff_type = arguments["staff_type"].to_s.strip.presence
    status = arguments["status"].to_s.strip.presence
    count_only = arguments["count_only"] == true
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    scope = build_scope(query, program_code:, staff_type:, status:)

    # by_status rides along in BOTH shapes: without it a model that forgets the
    # status filter reports retired staff as current ("74 lecturers" when 43
    # are active — prod 2026-09-12) and has no way to notice.
    by_status = status_breakdown(scope)

    if count_only
      { count: scope.count, by_status: by_status,
        filters: describe_filters(query, program_code, staff_type, status) }.to_json
    else
      total = scope.count
      staff = scope.limit(limit).map { |s| serialize(s) }
      result = { staff: staff, total: total, by_status: by_status }
      if total > staff.size
        result[:note] = "Showing #{staff.size} of #{total} results (#{describe_breakdown(by_status)})."
        result[:note] += " Pass status='active' to list only current staff." unless status
      end
      result.to_json
    end
  end

  # { "active" => 43, "retired" => 31 } for the whole match, ignoring limit.
  # The scope carries ORDER BY (invalid under GROUP BY with ONLY_FULL_GROUP_BY)
  # and DISTINCT over the program join, so count distinct staff ids per status.
  def self.status_breakdown(scope)
    scope.unscope(:order).group("staffs.status").distinct.count("staffs.id")
  end
  private_class_method :status_breakdown

  def self.describe_breakdown(by_status)
    STATUS_ORDER.filter_map { |st| "#{by_status[st]} #{st}" if by_status[st] }.join(", ")
  end
  private_class_method :describe_breakdown

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

    scope.order(STATUS_ORDER_SQL).order(:last_name, :first_name)
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
        "#{p.program_group.code} (#{p.year_started_be})"
      },
      teaching: teaching_summary(staff_member)
    }
  end
  private_class_method :serialize

  # Last few semesters of teaching — what, how many sections, and the summed
  # load_ratio — so "how much does X teach?" needs no second tool. Newest
  # first, capped at RECENT_TERMS semesters.
  def self.teaching_summary(staff_member)
    teachings = staff_member.teachings
                            .includes(section: { course_offering: [ :course, :semester ] })
                            .to_a
    return [] if teachings.empty?

    by_semester = teachings.group_by { |t| t.section.course_offering.semester }
    by_semester.keys.sort_by { |s| [ -s.year_be, -s.semester_number ] }.first(RECENT_TERMS).map do |sem|
      sem_teachings = by_semester[sem]
      {
        semester: sem.display_name,
        sections: sem_teachings.map { |t|
          offering = t.section.course_offering
          "#{offering.course.course_no} Sec #{t.section.section_number}"
        }.sort,
        section_count: sem_teachings.size,
        total_load: sem_teachings.sum { |t| t.load_ratio.to_f }.round(2)
      }
    end
  end
  private_class_method :teaching_summary

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
