require "test_helper"

class TermContextsControllerTest < ActionDispatch::IntegrationTest
  setup { post login_path, params: { username: users(:viewer).username, password: "password123" } }

  test "update stores a valid year and semester and redirects back" do
    patch term_context_path, params: { year_be: 2567, semester: 1 },
          headers: { "HTTP_REFERER" => reports_path }
    assert_redirected_to reports_path
    assert_equal({ "year_be" => 2567, "semester" => 1 }, session[:term_context])
  end

  test "update with a blank semester stores whole-year (nil semester)" do
    patch term_context_path, params: { year_be: 2567, semester: "" }
    assert_equal 2567, session[:term_context]["year_be"]
    assert_nil session[:term_context]["semester"]
  end

  test "update ignores an out-of-range semester (stores whole-year)" do
    patch term_context_path, params: { year_be: 2567, semester: 7 }
    assert_equal 2567, session[:term_context]["year_be"]
    assert_nil session[:term_context]["semester"]
  end

  test "update ignores a year that is not in the data" do
    patch term_context_path, params: { year_be: 1999, semester: 1 }
    assert_nil session[:term_context]
  end

  test "update falls back to root when there is no referer" do
    patch term_context_path, params: { year_be: 2567, semester: 1 }
    assert_redirected_to root_path
  end
end
