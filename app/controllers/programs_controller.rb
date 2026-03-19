class ProgramsController < ApplicationController
  before_action :set_program, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @programs = Program.all
  end

  def show
    @students = @program.students.order(admission_year_be: :desc, student_id: :asc)
    prepare_admission_chart_data
    prepare_gpa_chart_data
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

  def prepare_admission_chart_data
    students = @program.students
    all_counts = students.group(:admission_year_be, :enrollment_method).count
    years = all_counts.keys.map(&:first).uniq.sort
    methods = all_counts.keys.map(&:last).map { |m| m.presence || "Unknown" }.uniq.sort

    build_dataset = lambda { |counts|
      methods.each_with_object({}) do |method, hash|
        raw_key = method == "Unknown" ? nil : method
        hash[method] = years.map { |y| counts[[y, raw_key]] || 0 }
      end
    }

    datasets = { "all" => build_dataset.call(all_counts) }
    Student::STATUSES.each do |status|
      status_counts = students.where(status: status).group(:admission_year_be, :enrollment_method).count
      datasets[status] = build_dataset.call(status_counts)
    end

    @admission_chart_data = { labels: years, methods: methods, datasets: datasets }
  end

  def prepare_gpa_chart_data
    gpas = Grade.joins(:course, :student)
               .where(students: { program_id: @program.id })
               .where.not(grade_weight: nil)
               .group("grades.student_id")
               .pluck(Arel.sql("ROUND(SUM(grades.grade_weight * courses.credits) / SUM(courses.credits), 2)"))

    bin_edges = (0..7).map { |i| (i * 0.5).round(1) }
    labels = bin_edges.map { |lo| "#{format('%.1f', lo)}-#{format('%.1f', lo + 0.5)}" }
    counts = bin_edges.map do |lo|
      hi = lo + 0.5
      gpas.count { |g| g >= lo && (hi >= 4.0 ? g <= hi : g < hi) }
    end

    @gpa_chart_data = { labels: labels, counts: counts }
  end

  def program_params
    params.require(:program).permit(:program_code, :short_name, :name_en, :name_th, :degree_level, :degree_name, :degree_name_th, :field_of_study, :year_started, :active, :total_credit)
  end
end
