require "test_helper"

class RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin cannot create room" do
    assert_no_difference "Room.count" do
      post rooms_path, params: { room: { building: "ENG1", room_number: "101" } }
    end
    assert_redirected_to rooms_path
  end

  test "non-admin cannot update room" do
    room = rooms(:eng4_303)
    patch room_path(room), params: { room: { building: "ENG9" } }
    assert_redirected_to rooms_path
    assert_equal "ENG4", room.reload.building
  end

  test "non-admin cannot delete room" do
    room = rooms(:eng4_303)
    assert_no_difference "Room.count" do
      delete room_path(room)
    end
    assert_redirected_to rooms_path
  end
end
