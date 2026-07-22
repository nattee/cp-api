# Top individual students of one admission cohort by GPAX. The statistics
# view (averages/SD per term) is cohort_gpa; this is the named-people view.
class Line::Tools::CohortRankingTool
  DEFINITION = {
    description: "Rank the TOP INDIVIDUAL students of one admission cohort by GPAX (cumulative GPA). " \
                 "Use for 'who has the best GPAX in CP51?' or 'top 10 students of CEDT1'. Returns named " \
                 "students with rank, GPAX, and credits. Includes graduated students — alumni can be the " \
                 "answer. For cohort-wide STATISTICS (average GPA/GPAX, SD per term) use cohort_gpa instead.",
    parameters: {
      type: "object",
      properties: {
        program_code: {
          type: "string",
          description: "Program group code: CP, CEDT, CM, CS, SE, or CD. Required."
        },
        admission_year: {
          type: "integer",
          description: "Admission year. Buddhist Era (e.g. 2565) or Christian Era accepted; values below " \
                       "2400 are treated as C.E. Provide either admission_year or generation. " \
                       "Never derive this from cohort labels like 'CP51' — use generation for those."
        },
        generation: {
          type: "integer",
          description: "Generation/cohort index from labels like 'CP51' or 'รุ่น 51'. The number is a " \
                       "RUNNING INDEX starting at 1, NOT an abbreviated B.E. year. Provide either " \
                       "admission_year or generation."
        },
        limit: {
          type: "integer",
          description: "How many top students to return (default 5, max 20)."
        }
      },
      required: [ "program_code" ]
    }
  }.freeze

  MAX_LIMIT = 20
  DEFAULT_LIMIT = 5

  def self.call(arguments, user: nil)
    resolved = Line::Tools::CohortParam.resolve(
      program_code: arguments["program_code"],
      admission_year: arguments["admission_year"],
      generation: arguments["generation"]
    )
    return resolved.to_json if resolved[:error]

    group = resolved[:group]
    year_be = resolved[:admission_year_be]
    limit = (arguments["limit"] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)

    ranking = GradeStats::CohortRanking.call(program_group: group,
                                             admission_year_be: year_be, limit: limit)
    result = {
      program: group.code,
      admission_year_be: year_be,
      cohort: group.cohort_label(year_be),
      ranking: ranking
    }
    result[:note] = "No graded students found for this cohort." if ranking.empty?
    result.to_json
  end
end
