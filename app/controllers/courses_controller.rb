class CoursesController < ApplicationController
  before_action :set_course, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @courses = Course.all
  end

  # Grade stack order: bottom (worst) to top (best)
  GRADE_STACK_ORDER = %w[M F U W P V S D D+ C C+ B B+ A].freeze

  def show
    @grades_count = @course.grades.count
    @available_years = @course.grades.distinct.pluck(:year).sort.reverse
    if params[:year].present?
      @selected_year = params[:year].to_i
      @selected_semester = params[:semester].present? ? params[:semester].to_i : nil
      scope = @course.grades.includes(:student).where(year: @selected_year)
      scope = scope.where(semester: @selected_semester) if @selected_semester
      @course_grades = scope.order("students.student_id")
    end
    prepare_grade_distribution_chart

    @offerings = @course.course_offerings.includes(:semester, :sections).order("semesters.year_be DESC, semesters.semester_number DESC").references(:semesters)
  end

  def new
    @course = Course.new
  end

  def create
    @course = Course.new(course_params)
    if @course.save
      redirect_to @course, notice: "Course was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @course.update(course_params)
      redirect_to @course, notice: "Course was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @course.destroy!
    redirect_to courses_path, notice: "Course was successfully deleted."
  end

  private

  def set_course
    @course = Course.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to courses_path, alert: "Only admins can perform this action."
    end
  end

  def prepare_grade_distribution_chart
    counts = @course.grades
                    .where.not(grade: [ nil, "" ])
                    .group(:year, :semester, :grade)
                    .count

    # Build sorted term labels (year/semester)
    terms = counts.keys.map { |y, s, _| [ y, s ] }.uniq.sort
    labels = terms.map { |y, s| "#{y}/#{s}" }

    # Only include grades that appear in the data
    present_grades = counts.values.any? { |c| c > 0 } ? counts.keys.map { |_, _, g| g }.uniq : []
    grades = GRADE_STACK_ORDER.select { |g| present_grades.include?(g) }

    datasets = grades.map do |grade|
      data = terms.map { |y, s| counts[[y, s, grade]] || 0 }
      { grade: grade, data: data }
    end

    @grade_dist_chart_data = { labels: labels, datasets: datasets }
  end

  def course_params
    params.require(:course).permit(
      :name, :name_th, :name_abbr, :course_group, :course_no, :revision_year,
      :program_id, :is_gened, :department_code, :credits,
      :l_credits, :nl_credits, :l_hours, :nl_hours, :s_hours, :is_thesis
    )
  end
end
