module Book30
  # Undo the import: delete every book30_entries row and every book-sourced student
  # (source = book30). Refuses if one of them has acquired grades or advisorships.
  # The CM re-file is a correction, not part of the import, and is left alone.
  class Rollback
    def initialize(commit: false, io: $stdout)
      @commit = commit
      @io = io
    end

    def run
      book_students = Student.where(source: "book30")
      with_children = book_students.where(id: Grade.select(:student_id)).or(book_students.where(id: Advisorship.select(:student_id))).count
      if with_children.positive?
        @io.puts "Refusing: #{with_children} book-sourced students have grades or advisorships. Detach them first."
        return false
      end
      @io.puts "#{@commit ? 'DELETING' : 'DRY-RUN'}: #{Book30Entry.count} entries, #{book_students.count} students recorded from the book"
      return true unless @commit
      Student.transaction do
        Book30Entry.delete_all
        book_students.delete_all
      end
      true
    end
  end
end
