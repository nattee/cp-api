class CourseOfferingsController < ApplicationController
  before_action :set_semester, only: %i[index new create]
  before_action :set_course_offering, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    redirect_to @semester
  end

  def show
  end

  def new
    @course_offering = @semester.course_offerings.build
    @course_offering.sections.build(section_number: 1)
  end

  def create
    @course_offering = @semester.course_offerings.build(course_offering_params)

    if @course_offering.save
      redirect_to @course_offering, notice: "Course offering was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @semester = @course_offering.semester
  end

  def update
    if @course_offering.update(course_offering_params)
      redirect_to @course_offering, notice: "Course offering was successfully updated."
    else
      @semester = @course_offering.semester
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    semester = @course_offering.semester
    @course_offering.destroy!
    redirect_to semester, notice: "Course offering was successfully deleted."
  end

  private

  def set_semester
    @semester = Semester.find(params[:semester_id])
  end

  def set_course_offering
    @course_offering = CourseOffering.find(params[:id])
  end

  def require_admin
    redirect_path = @course_offering ? semester_path(@course_offering.semester) : semester_path(@semester)
    unless current_user.admin?
      redirect_to redirect_path, alert: "Only admins can perform this action."
    end
  end

  def course_offering_params
    params.require(:course_offering).permit(
      :course_id, :status, :remark,
      sections_attributes: [:id, :section_number, :remark, :_destroy,
        time_slots_attributes: [:id, :day_of_week, :start_time, :end_time, :room_id, :remark, :_destroy],
        teachings_attributes: [:id, :staff_id, :load_ratio, :_destroy]
      ]
    )
  end
end
