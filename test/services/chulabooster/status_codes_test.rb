require "test_helper"

class Chulabooster::StatusCodesTest < ActiveSupport::TestCase
  test "maps every known code to its family" do
    Chulabooster::StatusCodes::ACTIVE.each do |c|
      assert_equal "active", Chulabooster::StatusCodes.to_local(c), "code #{c}"
    end
    Chulabooster::StatusCodes::GRADUATED.each do |c|
      assert_equal "graduated", Chulabooster::StatusCodes.to_local(c), "code #{c}"
    end
    Chulabooster::StatusCodes::RETIRED.each do |c|
      assert_equal "retired", Chulabooster::StatusCodes.to_local(c), "code #{c}"
    end
  end

  test "unknown, blank, and nil codes map to nil" do
    assert_nil Chulabooster::StatusCodes.to_local("99")
    assert_nil Chulabooster::StatusCodes.to_local("")
    assert_nil Chulabooster::StatusCodes.to_local(nil)
    assert_nil Chulabooster::StatusCodes.to_local("active") # only raw CB codes map
  end

  test "tolerates surrounding whitespace" do
    assert_equal "graduated", Chulabooster::StatusCodes.to_local(" 13 ")
  end
end
