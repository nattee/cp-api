require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  test "every source declares the required identity fields" do
    DataSource::SOURCES.each do |src|
      %i[key name icon badge blurb].each do |field|
        assert src[field].present?, "#{src[:key].inspect}: #{field} must be present"
      end
    end
  end

  test "every source states both what it provides and what it does not" do
    DataSource::SOURCES.each do |src|
      assert src[:provides].present?,     "#{src[:key].inspect}: provides must be non-empty"
      assert src[:not_provides].present?, "#{src[:key].inspect}: not_provides must be non-empty"
    end
  end

  test "keys are unique" do
    keys = DataSource::SOURCES.map { |src| src[:key] }
    assert_equal keys.uniq, keys, "duplicate DataSource keys"
  end

  test "action paths resolve to real route helpers" do
    helpers = Rails.application.routes.url_helpers
    DataSource::SOURCES.filter_map { |src| src[:action] }.each do |action|
      assert helpers.respond_to?(action[:path]), "#{action[:path]} is not a route helper"
    end
  end

  test "every cited doc exists on disk" do
    DataSource::SOURCES.flat_map { |src| src[:docs] }.each do |doc|
      assert Rails.root.join(doc).exist?, "#{doc} is cited on /data_sources but does not exist"
    end
  end

  test "find returns the source for a key, nil otherwise" do
    assert_equal "CuGetReg", DataSource.find("cugetreg")[:name]
    assert_nil DataSource.find("no_such_source")
  end

  test "SOURCES is frozen" do
    assert DataSource::SOURCES.frozen?
  end
end
