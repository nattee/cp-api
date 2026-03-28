class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update destroy generate_line_code unlink_line]
  before_action :require_admin, only: %i[new create edit update destroy generate_line_code unlink_line]

  def index
    @users = User.all
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to @user, notice: "User was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: "User was successfully deleted."
  end

  def generate_line_code
    token = SecureRandom.alphanumeric(8).upcase
    @user.update!(
      line_link_token: token,
      line_link_token_expires_at: 24.hours.from_now
    )
    redirect_to @user, notice: "Linking code generated for #{@user.name}."
  end

  def unlink_line
    @user.update!(provider: nil, uid: nil, llm_consent: false, line_link_token: nil, line_link_token_expires_at: nil)
    redirect_to @user, notice: "LINE account unlinked for #{@user.name}."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to users_path, alert: "Only admins can perform this action."
    end
  end

  def user_params
    params.require(:user).permit(:username, :email, :name, :password, :password_confirmation, :role, :active, :provider, :uid, :llm_consent, :llm_model)
  end
end
