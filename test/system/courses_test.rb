require "application_system_test_case"

class CoursesTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index page shows all courses" do
    visit courses_path
    assert_text "Courses"
    assert_text courses(:intro_computing).course_no
    assert_text courses(:senior_project).name
    assert_text courses(:gened_course).name
  end

  test "index shows GenEd badge" do
    visit courses_path
    assert_selector ".badge-active", text: "GenEd"
  end

  test "show page displays course details" do
    course = courses(:intro_computing)
    visit course_path(course)

    assert_text course.name
    assert_text course.course_no
    assert_text course.revision_year.to_s
    assert_text course.name_th
    assert_text course.credits.to_s
  end

  test "show page links to program" do
    course = courses(:intro_computing)
    visit course_path(course)
    assert_selector "a", text: course.program.name_en
  end

  test "admin can create a course" do
    visit new_course_path

    fill_in "Course No", with: "2110999"
    fill_in "Revision year", with: 2565
    fill_in "Name (EN)", with: "New Course"
    tomselect_pick "Computer Engineering (Bachelor)", from: "Program"
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

  test "Tom Select renders for program field on new course" do
    visit new_course_path

    within find_tomselect_wrapper("Program") do
      assert_selector ".ts-control"
    end
  end

  private

  def find_tomselect_wrapper(label_text)
    label = find("label", text: label_text)
    container = label.ancestor(".mb-3", match: :first)
    container.find(".ts-wrapper")
  end

  def tomselect_pick(value, from:)
    wrapper = find_tomselect_wrapper(from)
    wrapper.find(".ts-control").click
    wrapper.find(".ts-dropdown .option", text: value).click
  end
end
