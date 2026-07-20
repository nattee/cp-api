# The launchpad at /. Deliberately queryless: it maps the app and links one
# level deeper than the 250px sidebar can, and it holds no counts or freshness
# data, so it cannot go stale or slow. Data-state questions live on
# /data_sources instead.
class HomeController < ApplicationController
  def index
    @report_sections = Reports::Catalog.grouped
  end
end
