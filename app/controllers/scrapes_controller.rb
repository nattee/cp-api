class ScrapesController < ApplicationController
  before_action :require_admin

  def index
    @scrapes = Scrape.recent.includes(:semester, :user)
  end

  def show
    @scrape = Scrape.find(params[:id])
  end

  def create
    semester = Semester.find(params[:scrape][:semester_id])
    scrape = Scrape.create!(
      semester: semester,
      user: current_user,
      source: params[:scrape][:source],
      study_program: params[:scrape][:study_program],
      state: "pending"
    )

    ScheduleScrapeJob.perform_later(scrape.id)
    scrape.update!(state: "pending")

    redirect_to scrape_path(scrape), notice: "Scrape job has been queued."
  end
end
