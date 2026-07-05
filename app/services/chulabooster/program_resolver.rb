module Chulabooster
  # Resolves a CB student row to a local Program, per the two-layer algorithm in
  # docs/chulabooster-program-crosswalk.md (§4, §6): major_code → program_group
  # (with the student_id-segment heuristic + year-existence fallback for the
  # shared 21100), then admission-year window → revision (majority-enrollment
  # default on twin ties). Loads all programs + enrollment counts once — build
  # one instance per sync run.
  class ProgramResolver
    MAJOR_TO_GROUP = { "21101" => "CS", "21102" => "SE", "21104" => "CEDT", "21103" => "21103" }.freeze
    CM_SEGMENTS = %w[70 72].freeze
    CD_SEGMENTS = %w[71 73].freeze
    # Year-existence fallback order: a graduate-range segment falls back to the
    # OTHER graduate group before bachelor (validated: the two pre-1998 seg-71
    # students are confirmed CM, not CP). See crosswalk doc §4.
    FALLBACK_ORDER = { "CD" => %w[CM CP], "CM" => %w[CD CP], "CP" => %w[CM CD] }.freeze

    Result = Struct.new(:program, :group, :flags, :failure, :heuristic, :twin_tie, keyword_init: true)

    def initialize
      @programs_by_group = Hash.new { |h, k| h[k] = [] }
      Program.includes(:program_group).where.not(program_groups: { code: "OTHER" }).each do |p|
        @programs_by_group[p.program_group.code] << [p.year_started_be, p]
      end
      @programs_by_group.each_value { |v| v.sort_by!(&:first) }
      @enrollment = Student.group(:program_id).count
    end

    def resolve(major_code:, student_id:, admission_year_be:)
      flags = []
      heuristic = false
      mc = major_code.to_s

      group = MAJOR_TO_GROUP[mc]
      if group.nil?
        return Result.new(failure: "unmapped major_code #{mc.inspect}", flags: flags) unless mc == "21100"
        heuristic = true
        group = group_from_student_id(student_id.to_s, flags)
        # Year-existence fallback (validated 146/146 on segment 71): if the guessed
        # group has no program old enough, the guess is impossible — try the others.
        if candidates(group, admission_year_be).empty?
          alt = FALLBACK_ORDER.fetch(group).find { |g| candidates(g, admission_year_be).any? }
          if alt
            flags << "no #{group} program existed by #{admission_year_be}; reassigned to #{alt}"
            group = alt
          end
        end
      end

      cands = candidates(group, admission_year_be)
      if cands.empty?
        return Result.new(group: group, flags: flags, heuristic: heuristic,
                          failure: "no #{group} program with year_started_be <= #{admission_year_be}")
      end

      best_year = cands.map(&:first).max
      twins = cands.select { |(y, _)| y == best_year }.map(&:last)
      program, twin_tie = pick_twin(twins, flags)
      Result.new(program: program, group: group, flags: flags, heuristic: heuristic, twin_tie: twin_tie)
    end

    private

    def candidates(group, admission_year_be)
      @programs_by_group[group].select { |(y, _)| y <= admission_year_be }
    end

    # 10-digit IDs carry a degree-level code at positions 2-3 (validated 99.97%);
    # 7-digit legacy IDs have no such segment — all 442 known ones are CP.
    def group_from_student_id(sid, flags)
      if sid.length == 10
        seg = sid[2, 2]
        group = if CM_SEGMENTS.include?(seg) then "CM"
                elsif CD_SEGMENTS.include?(seg) then "CD"
                else "CP"
                end
        flags << "program group #{group} inferred from student_id pattern " \
                 "(major_code 21100 is shared by CP/CM/CD) — verify"
        group
      else
        flags << "program group CP assumed (legacy #{sid.length}-digit student_id, " \
                 "major_code 21100; all known legacy-ID students are CP) — verify"
        "CP"
      end
    end

    # Twin ties: assign to the twin with the most current local students
    # (maximum-likelihood; see crosswalk doc §6a). Lower program_code only
    # when every twin is empty.
    def pick_twin(twins, flags)
      return [twins.first, false] if twins.size == 1

      chosen = twins.max_by { |p| [@enrollment.fetch(p.id, 0), -p.program_code.to_i] }
      counts = twins.sort_by(&:program_code).map { |p| "#{p.program_code}:#{@enrollment.fetch(p.id, 0)}" }
      flags << "program #{chosen.program_code} assumed among twins #{counts.join(', ')} " \
               "(majority enrollment) — verify"
      [chosen, true]
    end
  end
end
