require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index shows rooms" do
    visit rooms_path
    assert_text "ENG4"
    assert_text "303"
    assert_text "LAB1"
  end

  test "admin can add room inline" do
    visit rooms_path
    click_on "New Room"

    within("turbo-frame#room_form") do
      fill_in "Building", with: "ENG1"
      fill_in "Room No", with: "501"
      select "Lecture", from: "Type"
      fill_in "Capacity", with: "80"
      click_on "Add Room"
    end

    assert_text "Room was successfully created"
    assert_text "ENG1"
    assert_text "501"
  end

  test "admin can edit room inline" do
    visit rooms_path

    room = rooms(:eng4_303)
    find("a[href='#{edit_room_path(room)}']").click

    within("turbo-frame#room_form") do
      fill_in "Capacity", with: "100"
      click_on "Save"
    end

    assert_text "Room was successfully updated"
    assert_equal 100, room.reload.capacity
  end

  test "admin can delete room" do
    visit rooms_path
    room = rooms(:eng3_seminar)

    accept_confirm do
      find("a[href='#{room_path(room)}'][data-turbo-method='delete']").click
    end

    assert_text "Room was successfully deleted"
  end
end
