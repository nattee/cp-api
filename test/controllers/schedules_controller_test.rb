require "test_helper"

class SchedulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "index is accessible" do
    get schedules_path
    assert_response :success
  end

  test "room report is accessible" do
    get schedules_room_path
    assert_response :success
  end

  test "room report with filters" do
    get schedules_room_path, params: { semester_id: semesters(:sem_2568_1).id, room_id: rooms(:eng4_303).id }
    assert_response :success
  end

  test "staff report is accessible" do
    get schedules_staff_path
    assert_response :success
  end

  test "staff report with filters" do
    get schedules_staff_path, params: { semester_id: semesters(:sem_2568_1).id, staff_id: staffs(:lecturer_smith).id }
    assert_response :success
  end

  test "curriculum report is accessible" do
    get schedules_curriculum_path
    assert_response :success
  end

  test "curriculum report with filters" do
    get schedules_curriculum_path, params: { semester_id: semesters(:sem_2568_1).id, course_ids: [courses(:intro_computing).id] }
    assert_response :success
  end

  test "student report is accessible" do
    get schedules_student_path
    assert_response :success
  end

  test "student report with filters" do
    get schedules_student_path, params: { semester_id: semesters(:sem_2568_1).id, student_id: students(:active_student).id }
    assert_response :success
  end
end
