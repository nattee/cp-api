class ProgramGroupsController < ApplicationController
  include ProgramCharts

  def index
    @program_groups = ProgramGroup.where.not(code: "OTHER")
                                  .includes(:programs)
                                  .order(:id)

    # Student count by admission year × program group for overview chart
    counts = Student.joins(program: :program_group)
                    .where.not(program_groups: { code: "OTHER" })
                    .group("program_groups.code", :admission_year_be)
                    .count

    group_codes = @program_groups.map(&:code)
    years = counts.keys.map(&:last).uniq.sort.reverse  # newest first

    datasets = group_codes.map do |code|
      { code: code, data: years.map { |y| counts[[code, y]] || 0 } }
    end

    @overview_chart_data = { labels: years, datasets: datasets }
  end

  def show
    @program_group = ProgramGroup.find(params[:id])
    @programs = @program_group.programs.order(year_started: :desc)
    @students = Student.joins(:program).where(programs: { program_group_id: @program_group.id })
    prepare_admission_chart_data(@students)
    prepare_gpa_chart_data(@programs.pluck(:id))
  end
end
