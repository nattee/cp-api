require "application_system_test_case"

class StudentsTest < ApplicationSystemTestCase
  setup do
    # Login as admin
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index page shows all students" do
    visit students_path
    assert_text "Students"
    assert_text students(:active_student).student_id
    assert_text students(:graduated_student).full_name
    assert_text students(:on_leave_student).full_name
  end

  test "index shows status badges" do
    visit students_path
    assert_selector ".badge-active", text: "Active"
    assert_selector ".badge-graduated", text: "Graduated"
    assert_selector ".badge-on-leave", text: "On Leave"
  end

  test "show page displays student details" do
    student = students(:active_student)
    visit student_path(student)

    assert_text student.full_name
    assert_text student.student_id
    assert_text student.email
    assert_text student.admission_year.to_s
    assert_text student.discord
  end

  test "show page displays Thai name when present" do
    student = students(:active_student)
    visit student_path(student)
    assert_text student.full_name_th
  end

  test "show page hides sections with no data" do
    student = students(:on_leave_student)
    visit student_path(student)
    assert_no_text "Guardian"
    assert_no_text "Previous School"
  end

  test "admin can create a student" do
    visit new_student_path

    fill_in "Student ID", with: "9999900099"
    fill_in "First name", with: "New"
    fill_in "Last name", with: "Student"
    fill_in "Admission year", with: 2567
    click_on "Create Student"

    assert_text "Student was successfully created"
    assert_text "New Student"
    assert_text "9999900099"
  end

  test "create shows validation errors" do
    visit new_student_path
    click_on "Create Student"

    assert_text "prohibited this student from being saved"
    assert_text "can't be blank"
  end

  test "admin can edit a student" do
    student = students(:active_student)
    visit edit_student_path(student)

    fill_in "First name", with: "Updated"
    click_on "Update Student"

    assert_text "Student was successfully updated"
    assert_text "Updated"
  end

  test "admin can delete a student" do
    student = students(:active_student)
    visit students_path

    accept_confirm do
      find("a[href='#{student_path(student)}'][data-turbo-method='delete']").click
    end

    assert_text "Student was successfully deleted"
    assert_no_text student.student_id
  end
end
