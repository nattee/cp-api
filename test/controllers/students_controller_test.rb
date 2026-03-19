require "test_helper"

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
end
