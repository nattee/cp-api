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
    tomselect_pick "Computer Engineering (Bachelor)", from: "Program"
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

  # ---------------------------------------------------------------------------
  # JS control interaction tests
  # These test that Tom Select and Flatpickr actually work when clicked.
  # If a vendored JS library upgrade breaks these controls, these tests fail.
  # ---------------------------------------------------------------------------

  test "Tom Select renders and allows selecting a status" do
    visit edit_student_path(students(:active_student))

    # Tom Select replaces <select> with a .ts-wrapper div.
    # Verify it initialized (the wrapper exists and shows current value).
    within find_tomselect_wrapper("Status") do
      assert_text "Active"
    end

    # Open the dropdown and pick a different status
    tomselect_pick "Graduated", from: "Status"

    click_on "Update Student"
    assert_text "Student was successfully updated"
    assert_selector ".badge-graduated", text: "Graduated"
  end

  test "Tom Select shows Material Symbols icons in status options" do
    visit edit_student_path(students(:active_student))

    # Open the status dropdown
    find_tomselect_wrapper("Status").find(".ts-control").click

    # Each option should contain a Material Symbols icon span
    within ".ts-dropdown" do
      assert_selector ".option .material-symbols", minimum: 3
    end
  end

  test "Flatpickr renders and allows picking a graduation date" do
    visit edit_student_path(students(:graduated_student))

    # Flatpickr replaces the input with a hidden original + visible alt input.
    # Click the visible input to open the calendar.
    flatpickr_input = find_flatpickr_input("Graduation Date")
    flatpickr_input.click

    # The calendar popup should appear
    assert_selector ".flatpickr-calendar.open"

    # Click a day in the current month (pick day 15 to avoid edge cases)
    within ".flatpickr-calendar" do
      find(".flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)", text: /\A15\z/).click
    end

    # Calendar should close after selection
    assert_no_selector ".flatpickr-calendar.open"

    # The alt input should show a human-readable date
    assert_match(/15/, flatpickr_input.value)

    click_on "Update Student"
    assert_text "Student was successfully updated"
    assert_text "Graduation Date"
  end

  test "creating a student with Tom Select status and Flatpickr date" do
    visit new_student_path

    fill_in "Student ID", with: "9999900100"
    fill_in "First name", with: "Test"
    fill_in "Last name", with: "Integration"
    tomselect_pick "Computer Engineering (Bachelor)", from: "Program"
    fill_in "Admission year", with: 2565

    # Select "Graduated" via Tom Select
    tomselect_pick "Graduated", from: "Status"

    # Pick a graduation date via Flatpickr
    find_flatpickr_input("Graduation Date").click
    within ".flatpickr-calendar" do
      find(".flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)", text: /\A10\z/).click
    end

    click_on "Create Student"

    assert_text "Student was successfully created"
    assert_text "Test Integration"
    assert_selector ".badge-graduated", text: "Graduated"
    assert_text "Graduation Date"
  end

  private

  # Find the Tom Select wrapper (.ts-wrapper) associated with a labeled field.
  # Tom Select inserts the wrapper as a sibling of the original <select>.
  def find_tomselect_wrapper(label_text)
    label = find("label", text: label_text)
    container = label.ancestor(".mb-3", match: :first)
    container.find(".ts-wrapper")
  end

  # Open a Tom Select dropdown and pick an option by visible text.
  def tomselect_pick(value, from:)
    wrapper = find_tomselect_wrapper(from)
    wrapper.find(".ts-control").click
    wrapper.find(".ts-dropdown .option", text: value).click
  end

  # Find the visible Flatpickr input (the alt input) associated with a label.
  # Flatpickr hides the original input (type="hidden") and inserts a visible
  # alt input after it. The alt input has class "form-control input" (from
  # flatpickr's altInputClass default), NOT "flatpickr-input".
  def find_flatpickr_input(label_text)
    label = find("label", text: label_text)
    container = label.ancestor(".mb-3", match: :first)
    container.find("input[type='text']", visible: true)
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
