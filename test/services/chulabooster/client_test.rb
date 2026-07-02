require "test_helper"

class Chulabooster::ClientTest < ActiveSupport::TestCase
  def build_client
    Chulabooster::Client.new(config: { base_url: "https://cb.test", app_id: "id", app_secret: "sec" })
  end

  # Stub the HTTP seam to return a queue of [code, body] responses, recording each request.
  def stub_perform(client, responses)
    reqs = []
    client.define_singleton_method(:perform) do |request, _uri|
      reqs << request
      responses.shift
    end
    reqs
  end

  test "each_page follows next_cursor across pages and stops at null" do
    client = build_client
    stub_perform(client, [
      [200, { "count" => 2, "courses" => [{ "course_no" => "1" }, { "course_no" => "2" }], "next_cursor" => "abc" }.to_json],
      [200, { "count" => 1, "courses" => [{ "course_no" => "3" }], "next_cursor" => nil }.to_json]
    ])
    seen = []
    client.each_page("courses") { |rows, cursor| seen << [rows.map { |r| r["course_no"] }, cursor] }
    assert_equal [[["1", "2"], "abc"], [["3"], nil]], seen
  end

  test "each_row flattens rows across pages" do
    client = build_client
    stub_perform(client, [
      [200, { "count" => 1, "students" => [{ "student_id" => "a" }], "next_cursor" => "c" }.to_json],
      [200, { "count" => 1, "students" => [{ "student_id" => "b" }], "next_cursor" => nil }.to_json]
    ])
    ids = []
    client.each_row("students") { |r| ids << r["student_id"] }
    assert_equal %w[a b], ids
  end

  test "only issues GET requests (read-only)" do
    client = build_client
    reqs = stub_perform(client, [[200, { "count" => 0, "programs" => [], "next_cursor" => nil }.to_json]])
    client.each_page("programs") { |_, _| }
    assert_equal ["GET"], reqs.map(&:method)
  end

  test "unknown entity raises ArgumentError" do
    assert_raises(ArgumentError) { build_client.each_page("teachers") { |_, _| } }
  end

  test "403 raises PermissionError without retry" do
    client = build_client
    reqs = stub_perform(client, [[403, "permission_denied"]])
    assert_raises(Chulabooster::PermissionError) { client.each_page("students") { |_, _| } }
    assert_equal 1, reqs.length
  end

  test "401 raises AuthError" do
    client = build_client
    stub_perform(client, [[401, "unauthorized"]])
    assert_raises(Chulabooster::AuthError) { client.each_page("students") { |_, _| } }
  end

  test "retries on timeout then succeeds" do
    client = build_client
    calls = 0
    client.define_singleton_method(:perform) do |_request, _uri|
      calls += 1
      raise Timeout::Error if calls < 3
      [200, { "count" => 0, "courses" => [], "next_cursor" => nil }.to_json]
    end
    client.stub(:sleep, nil) { client.each_page("courses") { |_, _| } } if client.respond_to?(:stub)
    # Minitest core has no #stub on arbitrary objects here; override sleep on the instance instead:
    client.define_singleton_method(:sleep) { |_n| nil }
    calls = 0
    client.each_page("courses") { |_, _| }
    assert_equal 3, calls
  end
end
