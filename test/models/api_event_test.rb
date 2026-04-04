require "test_helper"

class ApiEventTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid event is valid" do
    event = ApiEvent.new(service: "llm", severity: "info", message: "OK")
    assert event.valid?
  end

  test "rejects invalid service" do
    event = ApiEvent.new(service: "invalid", severity: "info", message: "OK")
    assert_not event.valid?
    assert_includes event.errors[:service], "is not included in the list"
  end

  test "rejects invalid severity" do
    event = ApiEvent.new(service: "llm", severity: "critical", message: "OK")
    assert_not event.valid?
    assert_includes event.errors[:severity], "is not included in the list"
  end

  test "requires message" do
    event = ApiEvent.new(service: "llm", severity: "info")
    assert_not event.valid?
    assert_includes event.errors[:message], "can't be blank"
  end

  # --- .log ---

  test "log creates an event" do
    assert_difference "ApiEvent.count", 1 do
      ApiEvent.log(service: "llm", message: "test", severity: "info")
    end

    event = ApiEvent.last
    assert_equal "llm", event.service
    assert_equal "info", event.severity
    assert_equal "test", event.message
  end

  test "log stores optional fields" do
    ApiEvent.log(
      service: "llm", message: "OK", severity: "info",
      action: "tool_call", details: { tool: "echo" }, response_time_ms: 42
    )

    event = ApiEvent.last
    assert_equal "tool_call", event.action
    assert_equal({ "tool" => "echo" }, event.details)
    assert_equal 42, event.response_time_ms
  end

  test "log never raises even with invalid data" do
    assert_nothing_raised do
      ApiEvent.log(service: "INVALID", message: "test")
    end
  end

  # --- .timed ---

  test "timed records elapsed time" do
    result = ApiEvent.timed(service: "llm", action: "test") do
      sleep 0.01
      "done"
    end

    assert_equal "done", result

    event = ApiEvent.last
    assert_equal "llm", event.service
    assert_equal "test", event.action
    assert_equal "info", event.severity
    assert event.response_time_ms >= 10, "Expected at least 10ms, got #{event.response_time_ms}"
  end

  # --- Scopes ---

  test "recent scope orders by created_at desc" do
    old = ApiEvent.create!(service: "llm", severity: "info", message: "old", created_at: 1.hour.ago)
    new_event = ApiEvent.create!(service: "llm", severity: "info", message: "new")

    results = ApiEvent.recent.limit(2)
    assert_equal new_event, results.first
    assert_equal old, results.second
  end

  test "errors_since scope filters by severity and time" do
    ApiEvent.create!(service: "llm", severity: "info", message: "ok", created_at: 1.hour.ago)
    error = ApiEvent.create!(service: "llm", severity: "error", message: "fail", created_at: 30.minutes.ago)
    ApiEvent.create!(service: "llm", severity: "error", message: "old fail", created_at: 3.hours.ago)

    results = ApiEvent.errors_since(1.hour.ago)
    assert_includes results, error
    assert_equal 1, results.count
  end

  # --- .cleanup ---

  test "cleanup removes old events" do
    ApiEvent.create!(service: "llm", severity: "info", message: "old", created_at: 31.days.ago)
    recent = ApiEvent.create!(service: "llm", severity: "info", message: "recent")

    ApiEvent.cleanup
    assert_equal [recent], ApiEvent.all.to_a
  end
end
