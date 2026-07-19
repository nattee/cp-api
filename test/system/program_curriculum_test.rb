require "application_system_test_case"

class ProgramCurriculumTest < ApplicationSystemTestCase
  def sign_in(user)
    visit login_path
    fill_in "Username", with: user.username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "curriculum shows courses grouped by group label, constant order, ungrouped last" do
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))

    assert_text "Curriculum"
    headers = all("tr.table-group-header").map(&:text)
    # 2101-* codes are not in COURSE_GROUP_LABELS -> raw-suffix labels, alphabetical,
    # then Ungrouped (gened_cp has no tag).
    assert_equal 3, headers.size
    assert_match(/\AC\b/, headers[0])
    assert_match(/\AELEC\b/, headers[1])
    assert_match(/\AUngrouped\b/, headers[2])
    assert_text "2110101" # intro_computing under C
  end

  test "curriculum Type filter narrows to compulsory courses" do
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    # Default (All type): C, ELEC, Ungrouped groups all present.
    assert_equal 3, all("tr.table-group-header").size

    find("label[for='course-type-1']").click # Compulsory
    assert_equal 1, all("tr.table-group-header").size # only the compulsory (C) group
    assert_text "2110101"          # intro_computing (compulsory) stays
    assert_no_text "Senior Project" # elective, hidden
    assert_no_text "General Physics" # ungrouped gen-ed, hidden
  end

  test "curriculum Scope filter hides non-department courses" do
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    assert_text "General Physics" # 2103106 shown by default (curriculum defaults to All)

    find("label[for='course-scope-0']").click # 2110xxx
    assert_no_text "General Physics"           # 2103106 filtered out
    assert_text "2110101"                       # 2110 courses remain
    assert_text "Senior Project"
    assert_equal 2, all("tr.table-group-header").size # Ungrouped group emptied and hidden
  end

  test "admin adds a course with a group tag inline" do
    course = Course.create!(course_no: "2110888", revision_year_be: 2565, name: "Addable")
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    click_on "Add Course"

    within("turbo-frame#program_course_form") do
      find(".select2-selection").click
    end
    # Select2 appends its dropdown to <body>, not inside the turbo-frame
    # (see select2_controller.js), so the option must be found unscoped.
    find(".select2-results__option", text: "2110888 — Addable (2565)").click
    within("turbo-frame#program_course_form") do
      fill_in "Group Code", with: "2101-C"
      click_on "Add Course"
    end

    assert_text "Course was added to the program."
    assert_equal "2101-C",
                 ProgramCourse.find_by(program: programs(:cp_bachelor), course: course).course_group_code
  end

  test "admin edits a pairing's group tag inline" do
    pc = program_courses(:gened_cp)
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))
    find("a[href='#{edit_program_program_course_path(programs(:cp_bachelor), pc)}']").click

    within("turbo-frame#program_course_form") do
      fill_in "Group Code", with: "2101-GENED"
      click_on "Save"
    end

    assert_text "Course group was updated."
    assert_equal "2101-GENED", pc.reload.course_group_code
  end

  test "admin removes a link without deleting the course" do
    pc = program_courses(:senior_cp)
    course_id = pc.course_id
    sign_in users(:admin)
    visit program_path(programs(:cp_bachelor))

    accept_confirm do
      find("a[href='#{program_program_course_path(programs(:cp_bachelor), pc)}']").click
    end

    assert_text "Course was removed from the program."
    assert_nil ProgramCourse.find_by(id: pc.id)
    assert Course.exists?(course_id), "course itself must survive"
  end

  test "viewer sees the curriculum but no management controls" do
    sign_in users(:viewer)
    visit program_path(programs(:cp_bachelor))

    assert_text "Curriculum"
    assert_no_text "Add Course"
    assert_no_selector "a[href='#{edit_program_program_course_path(programs(:cp_bachelor), program_courses(:intro_cp))}']"
  end
end
