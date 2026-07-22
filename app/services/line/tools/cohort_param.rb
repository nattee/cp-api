# Shared resolution of the (program_code, admission_year | generation) cohort
# parameters used by cohort-centric tools. Returns { group:, admission_year_be: }
# on success or { error: "..." } (caller returns it as JSON). admission_year
# accepts B.E. or C.E. (values < 2400 treated as C.E.); generation resolves
# through the group's first_intake_year_be epoch.
module Line::Tools::CohortParam
  # Shared parameter-description constants: the cohort dialect must read
  # IDENTICALLY at every parameter site — drift here is how the next
  # CP51-read-as-2551 misfire happens. Tools append their own requirement
  # tail ("Requires program_code." / "Provide either admission_year or
  # generation.").
  GENERATION_DESCRIPTION =
    "Generation/cohort index from labels like 'CP51', 'CEDT01', or 'รุ่น 51'. " \
    "The number is a RUNNING INDEX starting at 1, NOT an abbreviated B.E. year: " \
    "CP51 = the 51st CP cohort (NOT admission year 2551). Never convert the " \
    "number to a year yourself — pass it here and the system resolves the " \
    "actual admission year.".freeze

  # Appended to every cohort-capable tool's admission_year description. The
  # rest of that description stays per-tool: era semantics genuinely differ
  # (student_lookup filters raw B.E.; cohort tools accept B.E. or C.E.).
  ADMISSION_YEAR_LABEL_WARNING =
    "Never derive this from cohort labels like 'CP51' — use generation for those.".freeze

  module_function

  def resolve(program_code:, admission_year: nil, generation: nil)
    code = program_code.to_s.strip.upcase
    return { error: "program_code is required" } if code.blank?

    group = ProgramGroup.find_by(code: code)
    unless group
      valid = ProgramGroup.order(:code).pluck(:code).join(", ")
      return { error: "Unknown program code #{code}. Valid codes: #{valid}" }
    end

    year = admission_year.to_i
    generation_index = generation.to_i
    if year.positive?
      { group: group, admission_year_be: year < 2400 ? year + 543 : year }
    elsif generation_index.positive?
      resolved = group.year_for_generation(generation_index)
      return { error: "#{group.code} has no recorded first intake year — ask by admission year instead" } unless resolved

      { group: group, admission_year_be: resolved }
    else
      { error: "admission_year or generation is required" }
    end
  end
end
