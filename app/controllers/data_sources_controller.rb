class DataSourcesController < ApplicationController
  before_action :require_admin

  def index
    @sources = DataSource::SOURCES
  end
end
