class ProgramsController < ApplicationController
  include ProgramCharts

  before_action :set_program, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @programs = Program.includes(:program_group).all
  end

  def show
    @students = @program.students.order(admission_year_be: :desc, student_id: :asc)
    prepare_admission_chart_data(@students)
    prepare_gpa_chart_data([@program.id])
  end

  def new
    @program = Program.new
    @program.program_group_id = params[:program_group_id] if params[:program_group_id]
  end

  def create
    @program = Program.new(program_params)

    if @program.save
      redirect_to @program, notice: "Program was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @program.update(program_params)
      redirect_to @program, notice: "Program was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @program.destroy!
    redirect_to programs_path, notice: "Program was successfully deleted."
  end

  private

  def set_program
    @program = Program.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to programs_path, alert: "Only admins can perform this action."
    end
  end

  def program_params
    params.require(:program).permit(:program_group_id, :program_code, :alternative_program_code,
                                    :short_name, :year_started, :active, :total_credit)
  end
end
