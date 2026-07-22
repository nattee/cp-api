class ProgramCoursesController < ApplicationController
  before_action :require_admin
  before_action :set_program
  before_action :set_program_course, only: %i[edit update destroy]

  def new
    @program_course = @program.program_courses.new
  end

  def create
    @program_course = @program.program_courses.new(create_params)
    if @program_course.save
      redirect_to @program, notice: "Course was added to the program."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @program_course.update(update_params)
      redirect_to @program, notice: "Course group was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @program_course.destroy!
    redirect_to @program, notice: "Course was removed from the program."
  end

  private

  def set_program
    @program = Program.find(params[:program_id])
  end

  def set_program_course
    @program_course = @program.program_courses.find(params[:id])
  end

  def create_params
    params.require(:program_course).permit(:course_id, :course_group_code)
  end

  # The linked course is immutable once created — editing only changes the tag.
  # (To move a link to another course: remove + re-add.)
  def update_params
    params.require(:program_course).permit(:course_group_code)
  end
end
