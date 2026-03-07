class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  layout "auth"

  def new
  end

  def create
    user = User.find_by(username: params[:username])

    if user&.active? && user&.authenticate(params[:password])
      session[:user_id] = user.id
      user.update_column(:last_sign_in_at, Time.current)
      redirect_to root_path, notice: "Signed in successfully."
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to login_path, notice: "Signed out successfully."
  end
end
