require "test_helper"

class GradeStats::StudentTranscriptTest < ActiveSupport::TestCase
  # Isolated records (course_no 997xxxx, student id 99xxx) — same convention
  # as cohort_gpa_tool_test — so fixture grades don't disturb the math.
  setup do
    @student = Student.create!(student_id: "9900000801", first_name: "T", last_name: "S",
                               first_name_th: "ท", last_name_th: "ส",
                               admission_year_be: 2599, status: "active",
                               program: programs(:cp_bachelor))
    @c1 = Course.create!(course_no: "9970011", name: "Transcript Course A",
                         revision_year_be: 2566, credits: 3)
    @c2 = Course.create!(course_no: "9970012", name: "Transcript Course B",
                         revision_year_be: 2566, credits: 3)
    @c3 = Course.create!(course_no: "9970013", name: "Transcript Course C",
                         revision_year_be: 2566, credits: 3)

    Grade.create!(student: @student, course: @c1, year_ce: 2056, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: @student, course: @c2, year_ce: 2056, semester: 1,
                  grade: "C+", grade_weight: 2.5, source: "imported")
    Grade.create!(student: @student, course: @c3, year_ce: 2056, semester: 2,
                  grade: "B", grade_weight: 3.0, source: "imported")
    # Withdrawn: no weight — must appear in courses but not affect GPA.
    Grade.create!(student: @student, course: @c1, year_ce: 2056, semester: 2,
                  grade: "W", grade_weight: nil, source: "imported")
  end

  test "terms are ascending with per-term GPA and cumulative GPAX" do
    result = GradeStats::StudentTranscript.call(student: @student)
    terms = result[:terms]

    assert_equal 2, terms.size
    assert_equal [ 2056, 1 ], [ terms[0][:year_ce], terms[0][:semester] ]
    assert_equal [ 2056, 2 ], [ terms[1][:year_ce], terms[1][:semester] ]

    # Term 1: (4.0*3 + 2.5*3) / 6 = 3.25
    assert_in_delta 3.25, terms[0][:gpa], 0.001
    assert_in_delta 3.25, terms[0][:gpax], 0.001

    # Term 2: 3.0; GPAX: (12 + 7.5 + 9) / 9 = 3.17
    assert_in_delta 3.0, terms[1][:gpa], 0.001
    assert_in_delta 3.17, terms[1][:gpax], 0.001
  end

  test "non-weighted grades appear as course rows but are excluded from GPA" do
    terms = GradeStats::StudentTranscript.call(student: @student)[:terms]
    term2_grades = terms[1][:courses].map { |c| c[:grade] }

    assert_includes term2_grades, "W"
    assert_equal 2, terms[1][:courses].size
  end

  test "student with no grades returns empty terms" do
    empty = Student.create!(student_id: "9900000802", first_name: "N", last_name: "G",
                            first_name_th: "น", last_name_th: "ก",
                            admission_year_be: 2599, status: "active",
                            program: programs(:cp_bachelor))
    assert_equal [], GradeStats::StudentTranscript.call(student: empty)[:terms]
  end
end
