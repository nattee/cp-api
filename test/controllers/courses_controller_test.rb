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
    assert_redirected_to root_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "Course.count" do
      post courses_path, params: { course: { name: "Test", course_no: "9999999", revision_year_be: 2565, program_id: programs(:cp_bachelor).id } }
    end
    assert_redirected_to root_path
  end

  test "non-admin cannot access edit" do
    get edit_course_path(courses(:intro_computing))
    assert_redirected_to root_path
  end

  test "non-admin cannot update" do
    course = courses(:intro_computing)
    patch course_path(course), params: { course: { name: "Hacked" } }
    assert_redirected_to root_path
    assert_equal "Introduction to Computing", course.reload.name
  end

  test "non-admin cannot delete" do
    assert_no_difference "Course.count" do
      delete course_path(courses(:intro_computing))
    end
    assert_redirected_to root_path
  end

  test "admin create assigns the program via program_ids (join row created)" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    assert_difference ["Course.count", "ProgramCourse.count"], 1 do
      post courses_path, params: { course: { name: "Ctrl New", course_no: "2110998", revision_year_be: 2565, program_ids: [programs(:cp_bachelor).id] } }
    end
    course = Course.find_by!(course_no: "2110998", revision_year_be: 2565)
    assert_includes course.programs, programs(:cp_bachelor)
  end

  test "admin update replaces the course program via program_ids" do
    post login_path, params: { username: users(:admin).username, password: "password123" }
    course = courses(:intro_computing) # linked to cp_bachelor
    patch course_path(course), params: { course: { name: course.name, program_ids: [programs(:cp_master).id] } }
    assert_equal [programs(:cp_master)], course.reload.programs.to_a
  end

  test "show lists each offering's teachers as staff links" do
    get course_path(courses(:intro_computing))
    assert_response :success
    assert_select "th", text: "Teachers"
    # intro_computing 2568/1: smith (JS) teaches sec 1+2, jones (JJ) co-teaches sec 2.
    assert_select "td a", text: "JS"
    assert_select "td a", text: "JJ"
  end
end
