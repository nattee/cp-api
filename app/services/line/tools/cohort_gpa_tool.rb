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
                       "accepted; values below 2400 are treated as C.E. Provide either admission_year or generation. " \
                       "Never derive this from cohort labels like 'CP51' — use generation for those."
        },
        generation: {
          type: "integer",
          description: "Generation/cohort index from labels like 'CP51', 'CEDT01', or 'รุ่น 51'. " \
                       "The number is a RUNNING INDEX starting at 1, NOT an abbreviated B.E. year: " \
                       "CP51 = the 51st CP cohort (NOT admission year 2551). Never convert the " \
                       "number to a year yourself — pass it here and the system resolves the " \
                       "actual admission year. Provide either admission_year or generation."
        }
      },
      required: [ "program_code" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    code = arguments["program_code"].to_s.strip.upcase
    year = arguments["admission_year"].to_i
    return { error: "program_code is required" }.to_json if code.blank?

    group = ProgramGroup.find_by(code: code)
    unless group
      valid = ProgramGroup.order(:code).pluck(:code).join(", ")
      return { error: "Unknown program code #{code}. Valid codes: #{valid}" }.to_json
    end

    generation = arguments["generation"].presence&.to_i

    admission_year_be =
      if !year.zero?
        # Students store admission year in B.E. — the opposite conversion from grades.
        year < 2400 ? year + 543 : year
      elsif generation
        year_be = group.year_for_generation(generation)
        return { error: "#{group.code} has no recorded first intake year — ask by admission year instead" }.to_json unless year_be
        year_be
      else
        return { error: "admission_year or generation is required" }.to_json
      end

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
