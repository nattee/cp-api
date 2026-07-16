require "test_helper"

class Reports::DataCoverageTest < ActiveSupport::TestCase
  # The report counts whole tables, so fixture rows would pollute every
  # assertion. Wipe term-scoped data (FK order: grades reference sections;
  # slots/teachings reference sections; sections reference offerings;
  # offerings and scrapes reference semesters) and build controlled terms.
  setup do
    Grade.delete_all
    TimeSlot.delete_all
    Teaching.delete_all
    Section.delete_all
    CourseOffering.delete_all
    Scrape.delete_all
    Semester.delete_all
    Student.delete_all
    @seq = 0
    @student = Student.create!(
      student_id: "9900000001", first_name: "T", last_name: "S",
      first_name_th: "ท", last_name_th: "ส", admission_year_be: 2500,
      status: "active", program: programs(:cp_bachelor)
    )
  end

  test "era rule: pre-era cells blank, zero within era red" do
    Semester.create!(year_be: 2565, semester_number: 1)  # before any grades
    Semester.create!(year_be: 2567, semester_number: 1)  # inside grades era, no grades
    make_grades(5, 2566, 1)
    make_grades(5, 2568, 1)

    rows = run_rows
    assert_equal ["2568/1", "2567/1", "2566/1", "2565/1"], rows.map { |r| r[:term] }

    pre_era = row(rows, "2565/1")
    assert_equal "—", pre_era[:grades]
    assert_nil pre_era[:grades_class]
    assert_equal "—", pre_era[:ungraded], "ungraded blanks alongside grades"

    missing = row(rows, "2567/1")
    assert_equal 0, missing[:grades]
    assert_equal "report-cell-missing", missing[:grades_class]

    ok = row(rows, "2566/1")
    assert_equal 5, ok[:grades]
    assert_nil ok[:grades_class]
  end

  test "a dataset with no data at all is all-blank, never red" do
    make_grades(3, 2566, 1)  # grades exist; schedule tables stay empty
    r = row(run_rows, "2566/1")
    assert_equal "—", r[:offerings]
    assert_nil r[:offerings_class]
  end

  test "low count vs same-semester median is yellow; summers compare with summers" do
    make_grades(10, 2564, 1)
    make_grades(10, 2565, 1)
    make_grades(10, 2566, 1)
    make_grades(4,  2567, 1)  # 4 < 0.5 * median(10,10,10) -> yellow
    make_grades(2,  2566, 3)  # small summers
    make_grades(2,  2567, 3)  # peer median 2 -> 2 is NOT < 1 -> no flag

    rows = run_rows
    assert_equal "report-cell-low", row(rows, "2567/1")[:grades_class]
    assert_nil row(rows, "2564/1")[:grades_class],
               "healthy year must not be flagged (median of others includes the low year)"
    assert_nil row(rows, "2566/3")[:grades_class],
               "summer must be judged against summers, not semester-1 medians"
    assert_nil row(rows, "2567/3")[:grades_class]
  end

  test "median of peers excludes zero terms so past missed terms don't drag the baseline" do
    make_grades(10, 2564, 1)
    make_grades(10, 2565, 1)
    Semester.create!(year_be: 2566, semester_number: 1)  # missed term: 0 grades
    make_grades(10, 2567, 1)

    rows = run_rows
    assert_equal "report-cell-missing", row(rows, "2566/1")[:grades_class]
    assert_nil row(rows, "2567/1")[:grades_class],
               "10 vs median(10, 10) — the zero term must not lower the median"
  end

  test "new students count on semester-1 rows only" do
    3.times { |i| make_student("66000000#{i}", 2566) }
    make_grades(1, 2566, 1)
    make_grades(1, 2566, 2)

    rows = run_rows
    assert_equal 3, row(rows, "2566/1")[:new_students]
    assert_equal "—", row(rows, "2566/2")[:new_students]
    assert_nil row(rows, "2566/2")[:new_students_class]
  end

  test "ungraded counts blank grades and is never flagged" do
    make_grades(2, 2566, 1)
    course = make_course
    Grade.create!(student: @student, course: course, year_ce: 2566 - 543,
                  semester: 1, grade: nil, source: "imported")

    r = row(run_rows, "2566/1")
    assert_equal 3, r[:grades]
    assert_equal 1, r[:ungraded]
    assert_nil r[:ungraded_class]
  end

  test "program-courses-only toggle restricts counts to curriculum-linked courses" do
    linked = make_course
    ProgramCourse.create!(program: programs(:cp_bachelor), course: linked)
    gened = make_course
    Grade.create!(student: @student, course: linked, year_ce: 2566 - 543,
                  semester: 1, grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: @student, course: gened, year_ce: 2566 - 543,
                  semester: 1, grade: "A", grade_weight: 4.0, source: "imported")
    sem = Semester.create!(year_be: 2566, semester_number: 1)
    [linked, gened].each do |c|
      off = CourseOffering.create!(course: c, semester: sem, status: "confirmed")
      Section.create!(course_offering: off, section_number: 1)
    end

    all_rows      = run_rows
    filtered_rows = Reports::DataCoverage.new("program_courses_only" => "1").run.rows

    assert_equal 2, row(all_rows, "2566/1")[:grades]
    assert_equal 1, row(filtered_rows, "2566/1")[:grades]
    assert_equal 2, row(all_rows, "2566/1")[:offerings]
    assert_equal 1, row(filtered_rows, "2566/1")[:offerings]
    assert_equal 1, row(filtered_rows, "2566/1")[:sections]
  end

  test "warning lists program revisions with no linked courses, never the placeholder" do
    make_grades(1, 2566, 1)
    Program.create!(program_code: "9999", year_started_be: 2571,
                    program_group: program_groups(:cp_group))
    Program.placeholder  # ensure the 0000 placeholder exists

    warning = Reports::DataCoverage.new({}).run.warning
    assert_equal "Programs with no courses linked", warning[:label]
    assert_includes warning[:items], "CP 2571 (9999)"
    assert warning[:items].none? { |item| item.include?("(0000)") }
  end

  test "new-students cell carries a per-program-group hover breakdown" do
    3.times { |i| make_student("66000000#{i}", 2566) }
    make_grades(1, 2566, 1)
    make_grades(1, 2566, 2)

    rows = run_rows
    assert_equal "CP: 3", row(rows, "2566/1")[:new_students_title]
    assert_nil row(rows, "2566/2")[:new_students_title], "breakdown only on semester-1 rows"
  end

  private

  def run_rows
    Reports::DataCoverage.new({}).run.rows
  end

  def row(rows, term)
    rows.find { |r| r[:term] == term } || flunk("no row for term #{term}")
  end

  def make_course
    @seq += 1
    Course.create!(course_no: "99#{format('%05d', @seq)}", name: "Coverage #{@seq}",
                   revision_year_be: 2565)
  end

  # N grades in one term = N throwaway courses for one student (grade
  # uniqueness is per student+course+term).
  def make_grades(count, year_be, semester)
    count.times do
      Grade.create!(student: @student, course: make_course, year_ce: year_be - 543,
                    semester: semester, grade: "A", grade_weight: 4.0,
                    credits_grant: 3, source: "imported")
    end
  end

  def make_student(id, admission_year_be)
    Student.create!(student_id: id, first_name: "T", last_name: "S",
                    first_name_th: "ท", last_name_th: "ส",
                    admission_year_be: admission_year_be,
                    status: "active", program: programs(:cp_bachelor))
  end
end
