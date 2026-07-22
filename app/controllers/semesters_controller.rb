class SemestersController < ApplicationController
  before_action :set_semester, only: %i[show edit update destroy export export_sections]
  before_action :require_admin, only: %i[new create edit update destroy]
  before_action -> { require_permission("courses.read") }

  def index
    @semesters = Semester.ordered
  end

  def show
    # Offerings load unscoped; the shared course filter narrows to the 2110
    # department client-side (its default). The Export Sections link carries the
    # department default explicitly for the server-side exporter.
    @course_offerings = @semester.course_offerings.includes(:course, sections: [{ teachings: :staff }, { time_slots: :room }])
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

  def export_sections
    exporter = Exporters::SemesterSectionsExporter.new(@semester, course_scope: course_scope_param)
    send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
  end

  private

  def set_semester
    @semester = Semester.find(params[:id])
  end

  # Same parse rule as SchedulesController#teaching_matrix: anything but an
  # explicit "all" means the department default.
  def course_scope_param
    params[:course_scope] == "all" ? "all" : "dept"
  end

  def semester_params
    params.require(:semester).permit(:year_be, :semester_number)
  end
end
