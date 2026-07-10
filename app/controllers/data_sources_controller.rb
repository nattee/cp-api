class DataSourcesController < ApplicationController
  before_action :require_admin

  def index
    @sources = DataSource::SOURCES
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can perform this action."
    end
  end
end
