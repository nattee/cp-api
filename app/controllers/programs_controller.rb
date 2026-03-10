class ProgramsController < ApplicationController
  before_action :set_program, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @programs = Program.all
  end

  def show
  end

  def new
    @program = Program.new
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
    params.require(:program).permit(:name_en, :name_th, :degree_level, :degree_name, :field_of_study, :year_started)
  end
end
