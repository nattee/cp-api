class ProgramGroupsController < ApplicationController
  include ProgramCharts

  def index
    @program_groups = ProgramGroup.where.not(code: "OTHER")
                                  .includes(:programs)
                                  .order(:degree_level, :name_en)
  end

  def show
    @program_group = ProgramGroup.find(params[:id])
    @programs = @program_group.programs.order(year_started: :desc)
    @students = Student.joins(:program).where(programs: { program_group_id: @program_group.id })
    prepare_admission_chart_data(@students)
    prepare_gpa_chart_data(@programs.pluck(:id))
  end
end
