require "test_helper"
require "roo"

class StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Login as viewer (non-admin)
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin can view index" do
    get students_path
    assert_response :success
  end

  test "non-admin can view show" do
    get student_path(students(:active_student))
    assert_response :success
  end

  test "non-admin cannot access new" do
    get new_student_path
    assert_redirected_to students_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "Student.count" do
      post students_path, params: { student: { student_id: "9999900099", first_name: "Test", last_name: "User", admission_year_be: 2567 } }
    end
    assert_redirected_to students_path
  end

  test "non-admin cannot access edit" do
    get edit_student_path(students(:active_student))
    assert_redirected_to students_path
  end

  test "non-admin cannot update" do
    student = students(:active_student)
    patch student_path(student), params: { student: { first_name: "Hacked" } }
    assert_redirected_to students_path
    assert_equal "Thanawat", student.reload.first_name
  end

  test "non-admin cannot delete" do
    assert_no_difference "Student.count" do
      delete student_path(students(:active_student))
    end
    assert_redirected_to students_path
  end

  test "non-admin cannot export" do
    get export_students_path
    assert_redirected_to students_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "admin export returns an xlsx attachment" do
    post login_path, params: { username: users(:admin).username, password: "password123" }

    get export_students_path
    assert_response :success
    assert_equal Exporters::Base::XLSX_CONTENT_TYPE, response.media_type
    assert_match(/filename="students\.xlsx"/, response.headers["Content-Disposition"])
    assert_equal "PK", response.body[0, 2]
  end

  test "admin export honours datatable filter params" do
    post login_path, params: { username: users(:admin).username, password: "password123" }

    # Filter to a single student via the global search param the datatable uses.
    target = students(:active_student)
    get export_students_path, params: { search: { value: target.student_id } }
    assert_response :success

    Tempfile.create(["export", ".xlsx"]) do |f|
      f.binmode
      f.write(response.body)
      f.flush
      sheet = Roo::Excelx.new(f.path)
      assert_equal 2, sheet.last_row, "expected header + exactly one matching student row"
      assert_equal target.student_id, sheet.row(2).first
    end
  end
end
