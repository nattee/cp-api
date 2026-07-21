# Per-term academic record for ONE student: courses + grades per semester,
# term GPA, and cumulative GPAX. The LINE-shaped version of the student show
# page's course history. Chula transcript naming: GPA = semester, GPAX =
# cumulative.
class Line::Tools::StudentGradesTool
  DEFINITION = {
    description: "Get one student's academic record term by term: the courses they took with grades, " \
                 "the semester GPA, and the cumulative GPAX (Chula convention: GPA = semester, " \
                 "GPAX = cumulative; term labels are Buddhist Era like '2567/1'). " \
                 "Use for questions like 'how did student X perform?', 'grades of 6530200321', " \
                 "'is X improving?', or 'did X take course Y?'. Search by student ID or name. " \
                 "For a student's profile without grades use student_lookup instead.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Student ID (e.g. '6530200321') or part of a name (Thai or English). Required."
        },
        semester: {
          type: "string",
          description: "Term in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2567/2'. Omit for all terms."
        }
      },
      required: [ "query" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    raise NotImplementedError, "student_grades is not implemented yet (eval-only definition)"
  end
end
