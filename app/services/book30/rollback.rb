module Book30
  # Undo the import: delete every book30_entries row and every placeholder student
  # (source = book30). Refuses if a placeholder has acquired grades or advisorships.
  # The CM re-file is a correction, not part of the import, and is left alone.
  class Rollback
    def initialize(commit: false, io: $stdout)
      @commit = commit
      @io = io
    end

    def run
      placeholders = Student.where(source: "book30")
      with_children = placeholders.where(id: Grade.select(:student_id)).or(placeholders.where(id: Advisorship.select(:student_id))).count
      if with_children.positive?
        @io.puts "Refusing: #{with_children} placeholder students have grades or advisorships. Detach them first."
        return false
      end
      @io.puts "#{@commit ? 'DELETING' : 'DRY-RUN'}: #{Book30Entry.count} entries, #{placeholders.count} placeholder students"
      return true unless @commit
      Student.transaction do
        Book30Entry.delete_all
        placeholders.delete_all
      end
      true
    end
  end
end
