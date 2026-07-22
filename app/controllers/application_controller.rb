class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login

  helper_method :current_user, :logged_in?, :current_term_context

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

  def current_term_context
    @current_term_context ||= TermContext.from_session(session)
  end

  def require_login
    unless logged_in?
      redirect_to login_path, alert: "You must be signed in."
    end
  end

  # Generalized read gate. Writes stay behind require_admin. nil-safe: an
  # expired session hits require_login first, but belt-and-braces here.
  def require_permission(key)
    unless current_user&.can?(key)
      redirect_to root_path, alert: "You are not authorized to view that page."
    end
  end

  # Kept as a named alias (not inlined at call sites) so the existing
  # `before_action :require_admin` lines across controllers keep working.
  def require_admin
    unless current_user&.can?("users.manage")
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
end
