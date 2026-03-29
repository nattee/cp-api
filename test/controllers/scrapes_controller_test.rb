require "test_helper"

class ScrapesControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin cannot create scrape" do
    assert_no_difference "Scrape.count" do
      post scrapes_path, params: { scrape: { semester_id: semesters(:sem_2568_1).id, source: "cugetreg", study_program: "S" } }
    end
    assert_redirected_to scrapes_path
  end

  test "viewer can view index" do
    get scrapes_path
    assert_response :success
  end

  test "viewer can view show" do
    get scrape_path(scrapes(:completed_scrape))
    assert_response :success
  end
end
