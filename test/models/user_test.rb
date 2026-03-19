require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_attributes
    {
      username: "newuser",
      email: "newuser@example.com",
      name: "New User",
      password: "password123",
      role: "viewer"
    }
  end

  # --- Validations ---

  test "valid user is valid" do
    user = User.new(valid_attributes)
    assert user.valid?
  end

  test "requires username" do
    user = User.new(valid_attributes.merge(username: nil))
    assert_not user.valid?
    assert_includes user.errors[:username], "can't be blank"
  end

  test "requires unique username" do
    User.create!(valid_attributes)
    duplicate = User.new(valid_attributes.merge(email: "other@example.com"))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:username], "has already been taken"
  end

  test "requires email" do
    user = User.new(valid_attributes.merge(email: nil))
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "requires unique email" do
    User.create!(valid_attributes)
    duplicate = User.new(valid_attributes.merge(username: "other"))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "rejects invalid email format" do
    %w[invalid not-an-email foo@].each do |bad_email|
      user = User.new(valid_attributes.merge(email: bad_email))
      assert_not user.valid?, "#{bad_email} should be invalid"
    end
  end

  test "accepts valid email format" do
    %w[user@example.com foo.bar@test.co.th a+b@domain.org].each do |good_email|
      user = User.new(valid_attributes.merge(email: good_email))
      assert user.valid?, "#{good_email} should be valid"
    end
  end

  test "requires name" do
    user = User.new(valid_attributes.merge(name: nil))
    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "requires role" do
    user = User.new(valid_attributes.merge(role: nil))
    assert_not user.valid?
    assert_includes user.errors[:role], "can't be blank"
  end

  test "rejects invalid role" do
    user = User.new(valid_attributes.merge(role: "superuser"))
    assert_not user.valid?
    assert_includes user.errors[:role], "is not included in the list"
  end

  test "accepts valid roles" do
    %w[admin editor viewer].each do |role|
      user = User.new(valid_attributes.merge(role: role))
      assert user.valid?, "#{role} should be a valid role"
    end
  end

  test "requires password" do
    user = User.new(valid_attributes.merge(password: nil))
    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  test "uid uniqueness is scoped to provider" do
    User.create!(valid_attributes.merge(provider: "line", uid: "U123"))
    duplicate = User.new(valid_attributes.merge(
      username: "other", email: "other@example.com",
      provider: "line", uid: "U123"
    ))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:uid], "has already been taken"
  end

  test "same uid with different provider is allowed" do
    User.create!(valid_attributes.merge(provider: "line", uid: "U123"))
    other = User.new(valid_attributes.merge(
      username: "other", email: "other@example.com",
      provider: "other", uid: "U123"
    ))
    assert other.valid?
  end

  test "nil uid is always allowed" do
    user1 = User.create!(valid_attributes)
    user2 = User.new(valid_attributes.merge(
      username: "other", email: "other@example.com"
    ))
    assert user2.valid?
    assert_nil user1.uid
    assert_nil user2.uid
  end

  # --- Role methods ---

  test "admin? returns true for admin role" do
    assert users(:admin).admin?
    assert_not users(:admin).editor?
    assert_not users(:admin).viewer?
  end

  test "editor? returns true for editor role" do
    assert users(:editor).editor?
    assert_not users(:editor).admin?
    assert_not users(:editor).viewer?
  end

  test "viewer? returns true for viewer role" do
    assert users(:viewer).viewer?
    assert_not users(:viewer).admin?
    assert_not users(:viewer).editor?
  end

  # --- Scopes ---

  test "active scope excludes inactive users" do
    active_users = User.active
    assert_includes active_users, users(:admin)
    assert_includes active_users, users(:editor)
    assert_includes active_users, users(:viewer)
    assert_not_includes active_users, users(:inactive)
  end

  # --- has_secure_password ---

  test "authenticate with correct password" do
    user = users(:admin)
    assert user.authenticate("password123")
  end

  test "authenticate with wrong password returns false" do
    user = users(:admin)
    assert_not user.authenticate("wrong")
  end

  # --- Defaults ---

  test "default role is viewer" do
    user = User.new
    assert_equal "viewer", user.role
  end

  test "default active is true" do
    user = User.new
    assert user.active?
  end
end
