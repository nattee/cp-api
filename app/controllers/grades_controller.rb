class GradesController < ApplicationController
  before_action :set_grade, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]
  before_action :require_manual_source, only: %i[edit update]

  def index
    if params[:year].present? && params[:semester].present?
      @grades = Grade.includes(:student, :course)
                     .for_term(params[:year], params[:semester])
      @filtered = true
    else
      @filtered = false
    end
    @available_years = Grade.distinct.pluck(:year).sort.reverse
  end

  def show; end

  def new
    @grade = Grade.new
  end

  def create
    @grade = Grade.new(grade_params)

    if @grade.save
      redirect_to @grade, notice: "Grade was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @grade.update(grade_params)
      redirect_to @grade, notice: "Grade was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @grade.destroy!
    redirect_to grades_path(year: @grade.year, semester: @grade.semester),
                notice: "Grade was successfully deleted."
  end

  private

  def set_grade
    @grade = Grade.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to grades_path, alert: "Only admins can perform this action."
    end
  end

  def require_manual_source
    if @grade.imported?
      redirect_to @grade, alert: "Imported grades cannot be edited. Re-import to update."
    end
  end

  def grade_params
    params.require(:grade).permit(
      :student_id, :course_id, :year, :semester, :grade, :grade_weight, :credits_grant
    )
  end
end
