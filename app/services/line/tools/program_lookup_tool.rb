# Lists the department's degree programs (หลักสูตร) with their curriculum
# revisions. This is the LLM's source of truth for program names and degree
# levels — without it the model invents expansions for the two-letter codes
# (a real incident: CM rendered as "Computer Mathematics", CD as "Computer
# Design"). The whole dataset is tiny (6 real groups, ~47 revisions), so one
# call returns everything nested; no pagination or separate revision tool.
class Line::Tools::ProgramLookupTool
  DEFINITION = {
    description: "Lists the department's degree programs/curricula (หลักสูตร) with official names " \
                 "(English + Thai), degree level, student counts, and curriculum revisions. " \
                 "Each program (e.g. CP) has one or more curriculum revisions (หลักสูตรปรับปรุง) " \
                 "identified by the B.E. year they started — 'หลักสูตร CP 2566' means the CP " \
                 "revision that started in 2566. Use for 'what programs are there?', what a " \
                 "program code stands for, degree levels, or curriculum revision questions. " \
                 "Never answer program names from memory. NOT for cohort labels like 'CP51' " \
                 "(program code + intake number, รุ่น) — those are student cohorts, not " \
                 "curricula; use student_lookup or cohort_gpa with the generation param.",
    parameters: {
      type: "object",
      properties: {
        program_code: {
          type: "string",
          description: "Program group code to filter by, e.g. 'CP', 'CEDT', 'CM', 'CS', 'SE', 'CD'. Omit to list all programs."
        },
        degree_level: {
          type: "string",
          enum: ProgramGroup::DEGREE_LEVELS,
          description: "Filter by degree level (ป.ตรี=bachelor, ป.โท=master, ป.เอก=doctoral). Omit to list all."
        }
      },
      required: []
    }
  }.freeze

  DEGREE_LEVEL_ORDER = ProgramGroup::DEGREE_LEVELS.each_with_index.to_h.freeze

  def self.call(arguments, user: nil)
    program_code = arguments["program_code"].to_s.strip.presence
    degree_level = arguments["degree_level"].to_s.strip.presence

    # Placeholder/legacy bookkeeping groups (OTHER, the CB "former track"
    # import artifact) have degree_name "Unknown" and would only confuse a
    # "what programs do we have?" answer.
    groups = ProgramGroup.includes(:programs).where.not(degree_name: "Unknown")

    if program_code
      groups = groups.where(code: program_code.upcase)
      if groups.empty?
        known = ProgramGroup.where.not(degree_name: "Unknown").order(:code).pluck(:code)
        return { error: "Unknown program code #{program_code}", known_codes: known }.to_json
      end
    end
    groups = groups.where(degree_level: degree_level.downcase) if degree_level

    totals = Student.group(:program_id).count
    actives = Student.where(status: "active").group(:program_id).count

    programs = groups.sort_by { |g| [ DEGREE_LEVEL_ORDER[g.degree_level] || 99, g.code ] }
                     .map { |g| group_json(g, totals, actives) }

    {
      programs: programs,
      note: "students_total counts all students ever recorded (including graduates); " \
            "students_active is the current enrollment."
    }.to_json
  end

  def self.group_json(group, totals, actives)
    revisions = group.programs.reject(&:placeholder?).sort_by(&:year_started_be)
    {
      code: group.code,
      name_en: group.name_en,
      name_th: group.name_th,
      degree_level: group.degree_level,
      degree: "#{group.degree_abbr} — #{group.degree_name} (#{group.degree_name_th})",
      first_intake_year_be: group.first_intake_year_be,
      students_total: revisions.sum { |p| totals[p.id] || 0 },
      students_active: revisions.sum { |p| actives[p.id] || 0 },
      revisions: revisions.map do |p|
        {
          year_started_be: p.year_started_be,
          program_code: p.program_code,
          total_credit: p.total_credit,
          active: p.active,
          students: totals[p.id] || 0
        }
      end
    }
  end
  private_class_method :group_json
end
