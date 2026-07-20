require "test_helper"

class NavigationTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  test "every area declares the full set of keys" do
    Navigation::AREAS.each do |area|
      assert_equal %i[key label description path_helper group access].sort,
                   area.keys.sort,
                   "#{area[:label]} has the wrong keys"
    end
  end

  test "every path_helper resolves to a route" do
    Navigation::AREAS.each do |area|
      assert_respond_to self, area[:path_helper],
                        "#{area[:label]} names a route helper that does not exist"
      assert_nothing_raised { public_send(area[:path_helper]) }
    end
  end

  test "every key has a Material Symbols icon" do
    Navigation::AREAS.each do |area|
      assert ApplicationHelper::RESOURCE_ICONS.key?(area[:key]),
             "#{area[:label]} has no RESOURCE_ICONS entry for #{area[:key].inspect}"
    end
  end

  test "groups and access use only the permitted values" do
    Navigation::AREAS.each do |area|
      assert_includes %i[records teaching_setup admin account], area[:group]
      assert_includes %i[all admin], area[:access]
    end
  end

  test "every admin-group area is admin access" do
    Navigation.for_group(:admin).each do |area|
      assert_equal :admin, area[:access], "#{area[:label]} is in :admin but open to all"
    end
  end

  test "for_group preserves declaration order" do
    labels = Navigation.for_group(:records).map { |a| a[:label] }
    assert_equal ["Programs", "Courses", "Staff", "Students", "Grades"], labels
  end

  test "visible_to hides admin areas from non-admins" do
    admin_areas = Navigation.visible_to(Navigation::AREAS, admin: true)
    viewer_areas = Navigation.visible_to(Navigation::AREAS, admin: false)

    assert_includes admin_areas.map { |a| a[:label] }, "Imports"
    assert_not_includes viewer_areas.map { |a| a[:label] }, "Imports"
    assert_includes viewer_areas.map { |a| a[:label] }, "Students"
  end
end
