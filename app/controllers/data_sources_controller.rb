class DataSourcesController < ApplicationController
  before_action :require_admin

  def index
    @sources = DataSource::SOURCES
  end

  # The 30-year book import report, live from book30_entries.
  def book30
    @summary = Book30::Summary.new
  end

  # Where every row came from, live counts by source.
  def provenance
    @summary = DataProvenance::Summary.new
  end
end
