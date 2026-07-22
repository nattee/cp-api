# Shared resolution of the (program_code, admission_year | generation) cohort
# parameters used by cohort-centric tools. Returns { group:, admission_year_be: }
# on success or { error: "..." } (caller returns it as JSON). admission_year
# accepts B.E. or C.E. (values < 2400 treated as C.E.); generation resolves
# through the group's first_intake_year_be epoch.
module Line::Tools::CohortParam
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
