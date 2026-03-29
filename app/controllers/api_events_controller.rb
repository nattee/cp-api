class ApiEventsController < ApplicationController
  before_action :require_admin

  def index
    @error_count_24h = ApiEvent.errors_since(24.hours.ago).count
    @api_events = ApiEvent.recent.limit(200)
    @api_events = @api_events.where(service: params[:service]) if params[:service].present?
    @api_events = @api_events.where(severity: params[:severity]) if params[:severity].present?
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
end
