require "test_helper"

class UserTest < ActiveSupport::TestCase
  def valid_attributes
    {
      username: "newuser",
      email: "newuser@example.com",
      name: "New User",
      password: "password123",
      role: roles(:staff)
    }
  end

  # --- Validations ---

  test "valid user is valid" do
    user = User.new(valid_attributes)
    assert user.valid?
  end

  test "blank llm_model from the form's Default option normalizes to nil and saves" do
    # The user form's "Default" select option submits "", but the inclusion
    # validation only allows nil — editing any user without a model preference
    # failed with "is not included in the list" (found on production 2026-07-16).
    user = User.new(valid_attributes.merge(llm_model: ""))
    assert user.valid?, user.errors.full_messages.join(", ")
    assert_nil user.llm_model
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
    # The public_info default (before_validation on: :create) only fires for
    # new records, so an existing user's role can still be explicitly cleared.
    user = User.create!(valid_attributes)
    user.role = nil
    assert_not user.valid?
    assert_includes user.errors[:role], "must exist"
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
  end

  test "admin? returns false for non-admin roles" do
    assert_not users(:viewer).admin?
    assert_not users(:editor).admin?
    assert_not users(:minimal).admin?
    assert_not users(:public_info).admin?
  end

  test "can? checks the role's effective permission set" do
    assert users(:admin).can?("users.manage")
    assert users(:viewer).can?("students.read_full")
    assert_not users(:viewer).can?("users.manage")
    assert users(:minimal).can?("students.read_minimal")
    assert_not users(:minimal).can?("students.read_full")
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

  test "new user defaults to public_info role when none given" do
    user = User.new(valid_attributes.except(:role))
    assert user.valid?, user.errors.full_messages.join(", ")
    assert_equal roles(:public_info), user.role
  end

  test "default active is true" do
    user = User.new
    assert user.active?
  end
end
