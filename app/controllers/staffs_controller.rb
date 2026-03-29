class StaffsController < ApplicationController
  before_action :set_staff, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @staffs = Staff.all
  end

  def show
    @teaching_semesters = Semester.joins(course_offerings: { sections: :teachings })
                                  .where(teachings: { staff_id: @staff.id })
                                  .distinct.ordered

    if @teaching_semesters.any?
      @selected_semester = if params[:semester_id].present?
                             Semester.find(params[:semester_id])
                           else
                             @teaching_semesters.first
                           end

      @teachings = Teaching.where(staff: @staff)
                          .joins(section: { course_offering: :semester })
                          .where(semesters: { id: @selected_semester.id })
                          .includes(section: { course_offering: [:course, :semester] })
    end
  end

  def new
    @staff = Staff.new
  end

  def create
    @staff = Staff.new(staff_params)

    if @staff.save
      redirect_to @staff, notice: "Staff was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @staff.update(staff_params)
      redirect_to @staff, notice: "Staff was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff.destroy!
    redirect_to staffs_path, notice: "Staff was successfully deleted."
  end

  private

  def set_staff
    @staff = Staff.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to staffs_path, alert: "Only admins can perform this action."
    end
  end

  def staff_params
    params.require(:staff).permit(
      :title, :academic_title, :first_name, :last_name,
      :first_name_th, :last_name_th, :staff_type,
      :email, :phone, :birthdate, :employment_date, :room, :status, :initials
    )
  end
end
