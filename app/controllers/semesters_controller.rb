class SemestersController < ApplicationController
  before_action :set_semester, only: %i[show edit update destroy export]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @semesters = Semester.ordered
  end

  def show
    @course_offerings = @semester.course_offerings.includes(:course, :sections)
  end

  def new
    @semester = Semester.new
  end

  def create
    @semester = Semester.new(semester_params)

    if @semester.save
      redirect_to @semester, notice: "Semester was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @semester.update(semester_params)
      redirect_to @semester, notice: "Semester was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @semester.destroy!
    redirect_to semesters_path, notice: "Semester was successfully deleted."
  end

  def export
    exporter = Exporters::ScheduleExporter.new(@semester)
    send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
  end

  private

  def set_semester
    @semester = Semester.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to semesters_path, alert: "Only admins can perform this action."
    end
  end

  def semester_params
    params.require(:semester).permit(:year_be, :semester_number)
  end
end
