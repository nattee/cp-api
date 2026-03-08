class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @students = Student.all
  end

  def show
  end

  def new
    @student = Student.new
  end

  def create
    @student = Student.new(student_params)

    if @student.save
      redirect_to @student, notice: "Student was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @student.update(student_params)
      redirect_to @student, notice: "Student was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @student.destroy!
    redirect_to students_path, notice: "Student was successfully deleted."
  end

  private

  def set_student
    @student = Student.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to students_path, alert: "Only admins can perform this action."
    end
  end

  def student_params
    params.require(:student).permit(
      :student_id, :first_name, :last_name, :first_name_th, :last_name_th,
      :email, :phone, :address, :discord, :line_id,
      :guardian_name, :guardian_phone, :previous_school, :enrollment_method,
      :admission_year, :status
    )
  end
end
