require "application_system_test_case"

class CoursesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index defaults to department (2110) courses; All reveals the rest" do
    visit courses_path
    assert_text "Courses"
    assert_text courses(:intro_computing).course_no  # 2110101 — department, shown
    assert_text courses(:senior_project).name        # 2110499 — department, shown
    assert_no_text courses(:gened_course).name       # 2103106 — hidden by default scope

    # Toggle the Scope filter to "All" (label #1; #0 is the 2110xxx default).
    find("label[for='course-scope-1']").click
    assert_text courses(:gened_course).name          # now visible
  end

  test "index shows GenEd badge (under All scope)" do
    visit courses_path
    # The only GenEd fixture course (2103106) is outside the 2110 default scope.
    find("label[for='course-scope-1']").click
    assert_selector ".badge-active", text: "GenEd"
  end

  test "show page displays course details" do
    course = courses(:intro_computing)
    visit course_path(course)

    assert_text course.name
    assert_text course.course_no
    assert_text course.revision_year_be.to_s
    assert_text course.name_th
    assert_text course.credits.to_s
  end

  test "show page links to program" do
    course = courses(:intro_computing)
    visit course_path(course)
    assert_selector "a", text: course.programs.first.name_en
  end

  test "admin can create a course" do
    visit new_course_path

    fill_in "Course No", with: "2110999"
    fill_in "Revision Year (B.E.)", with: 2565
    fill_in "Name (EN)", with: "New Course"
    select2_pick "Computer Engineering (Bachelor)", from: "Program"
    fill_in "Total Credits", with: 3
    click_on "Create Course"

    assert_text "Course was successfully created"
    assert_text "New Course"
    assert_text "2110999"
  end

  test "create shows validation errors" do
    visit new_course_path
    click_on "Create Course"

    assert_text "prohibited this course from being saved"
    assert_text "can't be blank"
  end

  test "admin can edit a course" do
    course = courses(:intro_computing)
    visit edit_course_path(course)

    fill_in "Name (EN)", with: "Updated Course Name"
    click_on "Update Course"

    assert_text "Course was successfully updated"
    assert_text "Updated Course Name"
  end

  test "admin can delete a course" do
    course = courses(:intro_computing)
    visit courses_path

    accept_confirm do
      find("a[href='#{course_path(course)}'][data-turbo-method='delete']").click
    end

    assert_text "Course was successfully deleted"
    assert_no_text course.course_no
  end

  test "editing a course linked to two programs keeps both links and their tags" do
    course = courses(:intro_computing) # linked to cp_bachelor with tag 2101-C
    ProgramCourse.create!(program: programs(:cp_master), course: course,
                          course_group_code: "2102-ELEC")

    visit edit_course_path(course)
    fill_in "Abbreviation", with: "INTRO2"
    click_on "Update Course"

    assert_text "Course was successfully updated"
    assert_equal 2, course.reload.programs.count
    tags = course.program_courses.order(:id).pluck(:course_group_code)
    assert_includes tags, "2101-C"
    assert_includes tags, "2102-ELEC"
  end

  test "Select2 renders for program field on new course" do
    visit new_course_path

    within find_select2_container("Program") do
      assert_selector ".select2-selection"
    end
  end

  private

  def find_select2_container(label_text)
    label = find("label", text: label_text)
    container = label.ancestor(".mb-3", match: :first)
    container.find(".select2-container")
  end

  def select2_pick(value, from:)
    container = find_select2_container(from)
    container.find(".select2-selection").click
    find(".select2-dropdown .select2-results__option", text: value).click
  end
end
