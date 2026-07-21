require "test_helper"

class SemestersControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin can view index" do
    get semesters_path
    assert_response :success
  end

  test "non-admin can view show" do
    get semester_path(semesters(:sem_2568_1))
    assert_response :success
  end

  test "non-admin cannot access new" do
    get new_semester_path
    assert_redirected_to semesters_path
    assert_equal "Only admins can perform this action.", flash[:alert]
  end

  test "non-admin cannot create" do
    assert_no_difference "Semester.count" do
      post semesters_path, params: { semester: { year_be: 2567, semester_number: 3 } }
    end
    assert_redirected_to semesters_path
  end

  test "non-admin cannot access edit" do
    get edit_semester_path(semesters(:sem_2568_1))
    assert_redirected_to semesters_path
  end

  test "non-admin cannot update" do
    semester = semesters(:sem_2568_1)
    patch semester_path(semester), params: { semester: { year_be: 2500 } }
    assert_redirected_to semesters_path
    assert_equal 2568, semester.reload.year_be
  end

  test "non-admin cannot delete" do
    assert_no_difference "Semester.count" do
      delete semester_path(semesters(:sem_2568_1))
    end
    assert_redirected_to semesters_path
  end

  test "export returns CSV download" do
    get export_semester_path(semesters(:sem_2568_1))
    assert_response :success
    assert_equal "text/csv", response.content_type.split(";").first
    assert_match(/attachment.*schedule_2568_1\.csv/, response.headers["Content-Disposition"])
    assert_match(/course_no/, response.body)
  end

  test "export_sections returns CSV download with all course scope" do
    get export_sections_semester_path(semesters(:sem_2568_1), course_scope: "all")
    assert_response :success
    assert_equal "text/csv", response.content_type.split(";").first
    assert_match(/attachment.*sections_2568_1\.csv/, response.headers["Content-Disposition"])
    assert_match(/course_no/, response.body)
  end

  test "export_sections with dept scope filters courses by course_no prefix" do
    # sem_2567_1 has both 2110% (2110101) and non-2110% (2103106) courses
    dept_response = begin
      get export_sections_semester_path(semesters(:sem_2567_1))
      response
    end
    assert_response :success
    assert_equal "text/csv", dept_response.content_type.split(";").first
    assert_match(/attachment.*sections_2567_1_dept\.csv/, dept_response.headers["Content-Disposition"])
    assert_match(/2110101/, dept_response.body)
    assert_no_match(/2103106/, dept_response.body)

    # Same semester with all scope includes all courses
    get export_sections_semester_path(semesters(:sem_2567_1), course_scope: "all")
    assert_response :success
    assert_match(/attachment.*sections_2567_1\.csv/, response.headers["Content-Disposition"])
    assert_match(/2110101/, response.body)
    assert_match(/2103106/, response.body)
  end
end
