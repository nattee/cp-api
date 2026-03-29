require "application_system_test_case"

class SemestersTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index shows semesters" do
    visit semesters_path
    assert_text "Semesters"
    assert_text "2568"
    assert_text "First"
    assert_text "Second"
  end

  test "admin can create semester" do
    visit new_semester_path

    fill_in "Year (B.E.)", with: 2567
    select "3 — Summer", from: "Semester"
    click_on "Create Semester"

    assert_text "Semester was successfully created"
    assert_text "2567/3"
  end

  test "create shows validation errors" do
    visit new_semester_path
    click_on "Create Semester"

    assert_text "prohibited this semester from being saved"
  end

  test "admin can edit semester" do
    semester = semesters(:sem_2568_2)
    visit edit_semester_path(semester)

    fill_in "Year (B.E.)", with: 2569
    click_on "Update Semester"

    assert_text "Semester was successfully updated"
    assert_text "2569/2"
  end

  test "admin can delete semester" do
    # Use sem_2568_2 which has no course offerings with sections that have time_slots/teachings
    semester = semesters(:sem_2568_2)
    visit semesters_path

    accept_confirm do
      find("a[href='#{semester_path(semester)}'][data-turbo-method='delete']").click
    end

    assert_text "Semester was successfully deleted"
  end

  test "show page lists course offerings" do
    semester = semesters(:sem_2568_1)
    visit semester_path(semester)

    assert_text "2568/1"
    assert_text "First Semester"
    assert_text "Course Offerings"
    assert_text courses(:intro_computing).course_no
    assert_text courses(:intro_computing).name
  end
end
