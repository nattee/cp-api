require "application_system_test_case"

class DataImportsTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "sidebar shows Imports link for admin" do
    visit root_path
    assert_selector "nav a", text: "Imports"
  end

  test "sidebar hides Imports link for non-admin" do
    click_on users(:admin).name
    page.execute_script("document.querySelector('button.dropdown-item').click()")
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit root_path
    assert_no_selector "nav a", text: "Imports"
  end

  test "non-admin cannot access imports" do
    click_on users(:admin).name
    page.execute_script("document.querySelector('button.dropdown-item').click()")
    visit login_path
    fill_in "Username", with: users(:viewer).username
    fill_in "Password", with: "password123"
    click_on "Sign In"

    visit data_imports_path
    assert_text "Only admins can access imports"
  end

  test "index page shows imports heading" do
    visit data_imports_path
    assert_text "Imports"
    assert_selector "a", text: "New Import"
  end

  test "Select2 works after validation error" do
    visit new_data_import_path

    # Submit without selecting anything — triggers validation errors
    click_on "Upload & Configure"
    assert_text "prohibited this import from being saved"

    # After validation error, Select2 on mode dropdown must still work
    select2_pick "Create or Update", from: "Mode"

    # Verify the selection stuck
    within find_select2_container("Mode") do
      assert_text "Create or Update"
    end
  end

  # --- Mapping flow ---

  test "upload redirects to mapping page" do
    visit new_data_import_path

    select2_pick "Student", from: "Target"
    select2_pick "Create only", from: "Mode"
    attach_file "File", csv_fixture_path("students_import.csv")

    click_on "Upload & Configure"

    assert_text "Configure Import"
    assert_text "Column Mapping"
  end

  test "mapping page auto-maps English headers" do
    di = create_pending_import("students_import.csv")
    visit mapping_data_import_path(di)

    # Auto-mapped selects should have labeled file headers selected (column letter prefix)
    assert_select_value "mapping[student_id]", "A: student_id"
    assert_select_value "mapping[first_name]", "B: first_name"
    assert_select_value "mapping[last_name]", "C: last_name"
    assert_select_value "mapping[admission_year_be]", "D: admission_year_be"
  end

  test "mapping page auto-maps Thai headers" do
    di = create_pending_import("students_thai_headers.csv")
    visit mapping_data_import_path(di)

    assert_select_value "mapping[student_id]", "A: รหัสนิสิต"
    assert_select_value "mapping[first_name]", "B: ชื่อ"
    assert_select_value "mapping[last_name]", "C: นามสกุล"
    assert_select_value "mapping[admission_year_be]", "D: ปีที่รับเข้า"
  end

  test "execute import from mapping page" do
    di = create_pending_import("students_import.csv")
    visit mapping_data_import_path(di)

    click_on "Run Import"

    assert_text "Import completed"
    assert_selector ".badge-completed", text: "Completed"
  end

  test "execute blocks when required field not mapped" do
    di = create_pending_import("students_import.csv")
    visit mapping_data_import_path(di)

    # Unmap a required field
    select2_pick_by_name "-- skip --", name: "mapping[admission_year_be]"
    click_on "Run Import"

    # Should redirect back to mapping with error
    assert_text "Required fields not mapped"
    assert_text "Admission Year"
  end

  test "fixed value mode shows input in preview column" do
    di = create_pending_import("students_minimal.csv")
    visit mapping_data_import_path(di)

    select2_pick_by_name "-- fixed value --", name: "mapping[status]"

    # The constant input should be visible
    assert_selector "[data-mapping-constant='status']", visible: true
  end

  test "import with fixed value applies to all rows" do
    di = create_pending_import("students_minimal.csv")
    visit mapping_data_import_path(di)

    select2_pick_by_name "-- fixed value --", name: "mapping[status]"
    find("[data-mapping-constant='status']").fill_in with: "on_leave"

    # Program is required — set as fixed value via dropdown
    select2_pick_by_name "-- fixed value --", name: "mapping[program_name]"
    find("[data-mapping-constant='program_name']").select programs(:cp_bachelor).name_en + " (#{programs(:cp_bachelor).year_started})"

    click_on "Run Import"

    assert_text "Import completed"
    student = Student.find_by(student_id: "9900300001")
    assert_equal "on_leave", student.status
  end

  test "show page displays column mapping audit" do
    di = create_pending_import("students_import.csv")
    visit mapping_data_import_path(di)
    click_on "Run Import"

    assert_text "Column Mapping"
    assert_text "Student ID"
    assert_text "student_id"
  end

  test "show page displays constant values in audit" do
    di = create_pending_import("students_minimal.csv")
    visit mapping_data_import_path(di)

    select2_pick_by_name "-- fixed value --", name: "mapping[status]"
    find("[data-mapping-constant='status']").fill_in with: "active"

    # Program is required — set as fixed value via dropdown
    select2_pick_by_name "-- fixed value --", name: "mapping[program_name]"
    find("[data-mapping-constant='program_name']").select programs(:cp_bachelor).name_en + " (#{programs(:cp_bachelor).year_started})"

    click_on "Run Import"

    assert_text "constant"
    assert_text "active"
  end

  # --- Retry flow ---

  test "failed import shows retry button" do
    di = create_failed_import
    visit data_import_path(di)

    assert_selector ".badge-failed", text: "Failed"
    assert_button "Retry"
  end

  test "retry sets failed import to retrying and redirects to mapping" do
    di = create_failed_import
    visit data_import_path(di)

    click_on "Retry"

    assert_text "Configure Import"
    di.reload
    assert_equal "retrying", di.state
  end

  # --- Pending import navigation ---

  test "pending import shows Configure link on index" do
    di = create_pending_import("students_import.csv")
    visit data_imports_path

    assert_selector "a[href='#{mapping_data_import_path(di)}']"
  end

  test "pending import shows Continue button on show page" do
    di = create_pending_import("students_import.csv")
    visit data_import_path(di)

    assert_selector "a", text: "Continue"
  end

  # --- Help popover ---

  test "program field has help icon" do
    di = create_pending_import("students_import.csv")
    visit mapping_data_import_path(di)

    assert_selector ".help-popover-trigger"
  end

  # --- Fixed value dropdown for relational fields ---

  test "program fixed value shows dropdown instead of text input" do
    di = create_pending_import("students_minimal.csv")
    visit mapping_data_import_path(di)

    select2_pick_by_name "-- fixed value --", name: "mapping[program_name]"

    # Should show a select element (dropdown), not a text input
    constant_el = find("[data-mapping-constant='program_name']", visible: true)
    assert_equal "select", constant_el.tag_name
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

  # Pick a Select2 option by the underlying select's name attribute.
  # Used for mapping selects which don't have labels.
  def select2_pick_by_name(value, name:)
    select_el = find("select[name='#{name}']", visible: false)
    container = select_el.sibling(".select2-container")
    container.find(".select2-selection").click
    find(".select2-dropdown .select2-results__option", text: value).click
  end

  def csv_fixture_path(filename)
    Rails.root.join("test/fixtures/files", filename).to_s
  end

  def assert_select_value(name, expected)
    select_el = find("select[name='#{name}']", visible: false)
    assert_equal expected, select_el.value, "Expected #{name} to be '#{expected}' but was '#{select_el.value}'"
  end

  def create_pending_import(fixture_filename)
    di = DataImport.new(
      target_type: "Student",
      mode: "create_only",
      state: "pending",
      user: users(:admin)
    )
    di.file.attach(
      io: File.open(csv_fixture_path(fixture_filename)),
      filename: fixture_filename,
      content_type: "text/csv"
    )
    di.save!
    di
  end

  def create_failed_import
    di = DataImport.new(
      target_type: "Student",
      mode: "create_only",
      state: "failed",
      user: users(:admin),
      error_message: "Test failure",
      error_count: 1,
      total_rows: 1
    )
    di.file.attach(
      io: File.open(csv_fixture_path("students_import.csv")),
      filename: "students_import.csv",
      content_type: "text/csv"
    )
    di.save!
    di
  end
end
