# Per-semester GPA statistics for one admission cohort (class year) of a
# program group. GPA = that semester's grade point average, GPAX = cumulative
# GPA through the term. Naming follows Chula transcripts (GPA = semester,
# GPAX = cumulative).
class Line::Tools::CohortGpaTool
  DEFINITION = {
    description: "Get per-semester GPA statistics for one admission cohort (class year) of a program. " \
                 "For each semester, returns gpa (that semester's grade point average) and gpax " \
                 "(cumulative GPA through that semester), each aggregated over the cohort: n, avg, sd, " \
                 "min, max, avg-2sd (minus2sd), avg+2sd (plus2sd). Terminology follows Chula transcripts " \
                 "(GPA = semester, GPAX = cumulative). Term labels are Buddhist Era, e.g. '2565/1'.",
    parameters: {
      type: "object",
      properties: {
        program_code: {
          type: "string",
          description: "Program group code: CP, CEDT, CM, CS, SE, or CD"
        },
        admission_year: {
          type: "integer",
          description: "Admission year of the cohort. Buddhist Era (e.g. 2565) or Christian Era (e.g. 2022) " \
                       "accepted; values below 2400 are treated as C.E."
        }
      },
      required: [ "program_code", "admission_year" ]
    }
  }.freeze

  def self.call(arguments)
    code = arguments["program_code"].to_s.strip.upcase
    year = arguments["admission_year"].to_i
    return { error: "program_code and admission_year are required" }.to_json if code.blank? || year.zero?

    group = ProgramGroup.find_by(code: code)
    unless group
      valid = ProgramGroup.order(:code).pluck(:code).join(", ")
      return { error: "Unknown program code #{code}. Valid codes: #{valid}" }.to_json
    end

    # Students store admission year in B.E. — the opposite conversion from grades.
    admission_year_be = year < 2400 ? year + 543 : year
    data = GradeStats::CohortGpa.call(program_group: group, admission_year_be: admission_year_be)

    {
      program: group.code,
      admission_year_be: admission_year_be,
      terms: data[:terms].map do |t|
        { term: "#{t[:year_ce] + 543}/#{t[:semester]}",
          year_ce: t[:year_ce], semester: t[:semester],
          gpa: t[:gpa], gpax: t[:gpax] }
      end
    }.to_json
  end
end
