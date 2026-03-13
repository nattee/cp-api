class CoursesController < ApplicationController
  before_action :set_course, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @courses = Course.all
  end

  def show; end

  def new
    @course = Course.new
  end

  def create
    @course = Course.new(course_params)
    if @course.save
      redirect_to @course, notice: "Course was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @course.update(course_params)
      redirect_to @course, notice: "Course was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy!
    redirect_to courses_path, notice: "Course was successfully deleted."
  end

  private

  def set_course
    @course = Course.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to courses_path, alert: "Only admins can perform this action."
    end
  end

  def course_params
    params.require(:course).permit(
      :name, :name_th, :name_abbr, :course_group, :course_no, :revision_year,
      :program_id, :is_gened, :department_code, :credits,
      :l_credits, :nl_credits, :l_hours, :nl_hours, :s_hours, :is_thesis
    )
  end
end
