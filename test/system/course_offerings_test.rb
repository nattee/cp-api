require "application_system_test_case"

class CourseOfferingsTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "admin can create offering with sections" do
    semester = semesters(:sem_2568_2)
    visit new_semester_course_offering_path(semester)

    select2_pick "2110101 — Introduction to Computing (2565)", from: "Course"
    # Section 1 is pre-built by the controller
    fill_in_section(0, number: 1)
    click_on "Create Course offering"

    assert_text "Course offering was successfully created"
    assert_text "Section 1"
  end

  test "admin can add sections dynamically" do
    semester = semesters(:sem_2568_2)
    visit new_semester_course_offering_path(semester)

    select2_pick "2110101 — Introduction to Computing (2565)", from: "Course"
    fill_in_section(0, number: 1)

    click_on "Add Section"
    fill_in_section(1, number: 2, remark: "Lab group")
    click_on "Create Course offering"

    assert_text "Course offering was successfully created"
    assert_text "Section 1"
    assert_text "Section 2"
    assert_text "Lab group"
  end

  test "admin can remove sections dynamically" do
    semester = semesters(:sem_2568_2)
    visit new_semester_course_offering_path(semester)

    select2_pick "2110101 — Introduction to Computing (2565)", from: "Course"
    fill_in_section(0, number: 1)

    click_on "Add Section"
    fill_in_section(1, number: 2)

    # Remove the second section
    section_cards = all(".section-fields")
    section_cards.last.find("button[data-action='nested-fields#remove']").click

    click_on "Create Course offering"

    assert_text "Course offering was successfully created"
    assert_text "Section 1"
    assert_no_text "Section 2"
  end

  test "show page displays sections with time slots and staff" do
    offering = course_offerings(:intro_computing_2568_1)
    visit course_offering_path(offering)

    assert_text offering.course.course_no
    assert_text offering.course.name
    assert_text "Section 1"
    assert_text "Section 2"
    # Time slots from fixtures
    assert_text "Monday"
    assert_text "Wednesday"
    assert_text "09:00-10:30"
    # Staff from fixtures
    assert_text staffs(:lecturer_smith).display_name
  end

  test "admin can add time slots and teachings to sections" do
    semester = semesters(:sem_2568_2)
    visit new_semester_course_offering_path(semester)

    select2_pick "2110101 — Introduction to Computing (2565)", from: "Course"
    fill_in_section(0, number: 1)

    # Add a time slot inside the first section
    within all(".section-fields")[0] do
      find("button", text: "Time Slot").click
      slot_row = all(".time-slot-fields").last
      within slot_row do
        find("select[name*='day_of_week']").select("Mon")
        all("input[type='time']")[0].set("09:00")
        all("input[type='time']")[1].set("10:30")
      end

      # Add a teaching and pick staff via Select2
      find("button", text: "Staff").click
      teaching_row = all(".teaching-fields").last
      within teaching_row do
        find(".select2-container").click
      end
    end
    # Select2 dropdown renders at body level, outside the within scope
    find(".select2-dropdown .select2-results__option", text: staffs(:lecturer_smith).display_name).click

    click_on "Create Course offering"

    assert_text "Course offering was successfully created"
    assert_text "Section 1"
    assert_text "Monday"
    assert_text "09:00-10:30"
    assert_text staffs(:lecturer_smith).display_name
  end

  test "admin can edit offering" do
    offering = course_offerings(:intro_computing_2568_1)
    visit edit_course_offering_path(offering)

    # Change status using select2
    select2_pick "Cancelled", from: "Status"
    click_on "Update Course offering"

    assert_text "Course offering was successfully updated"
    assert_text "Cancelled"
  end

  test "non-admin sees read-only show" do
    # Log out and re-login as viewer
    visit logout_path
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    offering = course_offerings(:intro_computing_2568_1)
    visit course_offering_path(offering)

    assert_text offering.course.name
    assert_no_selector "a", text: "Edit"
  end

  private

  def fill_in_section(index, number:, remark: nil)
    section_cards = all(".section-fields")
    within section_cards[index] do
      fill_in "Section Number", with: number
      fill_in "Remark", with: remark if remark
    end
  end

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
