class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login

  helper_method :current_user, :logged_in?

  private

  def current_user
    if ENV["AUTO_LOGIN"].present?
      @current_user ||= User.find_by(id: ENV["AUTO_LOGIN"])
    else
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    unless logged_in?
      redirect_to login_path, alert: "You must be signed in."
    end
  end
end
