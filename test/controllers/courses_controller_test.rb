require "test_helper"

class CoursesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin can view index" do
    get courses_path
    assert_response :success
  end

  test "non-admin can view show" do
    get course_path(courses(:intro_computing))
    assert_response :success
  end

  test "non-admin cannot access new" do
    get new_course_path
    assert_redirected_to courses_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "Course.count" do
      post courses_path, params: { course: { name: "Test", course_no: "9999999", revision_year: 2565, program_id: programs(:cp_bachelor).id } }
    end
    assert_redirected_to courses_path
  end

  test "non-admin cannot access edit" do
    get edit_course_path(courses(:intro_computing))
    assert_redirected_to courses_path
  end

  test "non-admin cannot update" do
    course = courses(:intro_computing)
    patch course_path(course), params: { course: { name: "Hacked" } }
    assert_redirected_to courses_path
    assert_equal "Introduction to Computing", course.reload.name
  end

  test "non-admin cannot delete" do
    assert_no_difference "Course.count" do
      delete course_path(courses(:intro_computing))
    end
    assert_redirected_to courses_path
  end
end
