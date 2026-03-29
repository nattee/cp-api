require "test_helper"

class CourseOfferingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin can view show" do
    get course_offering_path(course_offerings(:intro_computing_2568_1))
    assert_response :success
  end

  test "non-admin cannot access new" do
    get new_semester_course_offering_path(semesters(:sem_2568_1))
    assert_redirected_to semester_path(semesters(:sem_2568_1))
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "CourseOffering.count" do
      post semester_course_offerings_path(semesters(:sem_2568_2)), params: {
        course_offering: { course_id: courses(:gened_course).id, status: "planned" }
      }
    end
    assert_redirected_to semester_path(semesters(:sem_2568_2))
  end

  test "non-admin cannot access edit" do
    get edit_course_offering_path(course_offerings(:intro_computing_2568_1))
    assert_redirected_to semester_path(semesters(:sem_2568_1))
  end

  test "non-admin cannot update" do
    offering = course_offerings(:intro_computing_2568_1)
    patch course_offering_path(offering), params: { course_offering: { status: "cancelled" } }
    assert_redirected_to semester_path(offering.semester)
    assert_equal "confirmed", offering.reload.status
  end

  test "non-admin cannot delete" do
    assert_no_difference "CourseOffering.count" do
      delete course_offering_path(course_offerings(:senior_project_2568_1))
    end
    assert_redirected_to semester_path(semesters(:sem_2568_1))
  end
end
