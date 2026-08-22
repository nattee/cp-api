# One-off: dissolves the synthetic program row "0999". The real B.E. 2540
# M.Sc.-CS registration it stood in for is the special program
# (ภาคนอกเวลาราชการ, CB program 175211001997) — recorded per-student in
# students.study_track, not a curriculum revision of the regular CS lineage.
# Students move to the latest remaining CS revision started on or before
# their admission year (0038 for the actual 2540-2556 population); the row
# is then destroyed (its program_courses cascade). See
# docs/superpowers/specs/2026-08-21-cs-study-track-design.md.
class DissolveProgram0999
  def initialize(commit: false, io: $stdout)
    @commit = commit
    @io = io
  end

  def run
    program = Program.find_by(program_code: "0999")
    return @io.puts("0999 not found — already dissolved.") unless program

    replacements = program.program_group.programs.where.not(id: program.id)
    moves = program.students.order(:admission_year_be, :student_id).map do |student|
      target = replacements.where(year_started_be: ..student.admission_year_be)
                           .order(year_started_be: :desc).first
      raise "no replacement revision for #{student.student_id} (#{student.admission_year_be})" unless target
      [ student, target ]
    end

    moves.group_by { |student, target| [ student.admission_year_be, target.program_code ] }.sort.each do |(year, code), pairs|
      @io.puts "  #{year} -> #{code}: #{pairs.size}"
    end
    @io.puts "program_courses rows on 0999 (will cascade on destroy): #{program.program_courses.count}"

    if @commit
      Program.transaction do
        moves.each { |student, target| student.update!(program: target) }
        raise "students still attached to 0999" unless program.students.reload.count.zero?
        program.destroy!
      end
      @io.puts "COMMITTED: #{moves.size} students moved, 0999 destroyed."
    else
      @io.puts "DRY-RUN: would move #{moves.size} students, then destroy 0999."
    end
  end
end
