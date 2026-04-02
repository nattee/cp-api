class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @admission_years = Student.distinct.order(admission_year_be: :desc).pluck(:admission_year_be)
    @programs = Program.order(:name_en).pluck(:name_en)
  end

  def datatable
    draw = params[:draw].to_i
    start = params[:start].to_i
    length = params[:length].to_i
    search_value = params.dig(:search, :value).to_s.strip
    order_col = params.dig(:order, "0", :column).to_i
    order_dir = params.dig(:order, "0", :dir) == "desc" ? "DESC" : "ASC"

    # Column index to DB column (matches thead order)
    columns_map = {
      0 => "students.student_id",
      1 => "students.first_name",
      2 => "programs.name_en",
      3 => "programs.degree_level",
      4 => "students.admission_year_be",
      5 => "students.status"
    }

    base = Student.includes(:program).references(:program)
    records_total = Student.count

    if search_value.present?
      like = "%#{Student.sanitize_sql_like(search_value)}%"
      base = base.where(
        "students.student_id LIKE :q OR students.first_name LIKE :q OR students.last_name LIKE :q " \
        "OR students.first_name_th LIKE :q OR students.last_name_th LIKE :q " \
        "OR programs.name_en LIKE :q",
        q: like
      )
    end

    # Column-level filters (sent by DataTables column().search())
    col_search_program = params.dig(:columns, "2", :search, :value).to_s.strip
    col_search_degree = params.dig(:columns, "3", :search, :value).to_s.strip
    col_search_year = params.dig(:columns, "4", :search, :value).to_s.strip
    base = base.where("programs.name_en" => col_search_program) if col_search_program.present?
    base = base.where("programs.degree_level" => col_search_degree) if col_search_degree.present?
    base = base.where("students.admission_year_be" => col_search_year.to_i) if col_search_year.present?

    records_filtered = base.count
    order_column = columns_map[order_col] || "students.student_id"
    students = base.order(Arel.sql("#{order_column} #{order_dir}"))
                   .offset(start).limit(length)

    is_admin = current_user.admin?

    data = students.map do |student|
      [
        student.student_id,
        student.display_name,
        student.program&.name_en.to_s,
        ("<span class=\"badge badge-#{student.program&.degree_level}\">#{student.program&.degree_level&.titleize}</span>" if student.program).to_s,
        student.admission_year_be,
        render_to_string(partial: "students/status_badge", locals: { student: student }, layout: false),
        render_to_string(partial: "students/actions", locals: { student: student, is_admin: is_admin }, layout: false)
      ]
    end

    render json: { draw: draw, recordsTotal: records_total, recordsFiltered: records_filtered, data: data }
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
    if action_name == "show"
      @grades = @student.grades.includes(course: :program)
      load_schedule_data
    end
  end

  def load_schedule_data
    @schedule_semesters = Semester.joins(:course_offerings)
                                  .where(course_offerings: { course_id: @grades.select(:course_id) })
                                  .distinct.ordered

    if @schedule_semesters.any?
      @schedule_semester = if params[:semester_id].present?
                             Semester.find(params[:semester_id])
                           else
                             @schedule_semesters.first
                           end

      term_grades = @grades.where(year: @schedule_semester.year_be, semester: @schedule_semester.semester_number)
      @schedule_entries = term_grades.map do |grade|
        offering = CourseOffering.find_by(course: grade.course, semester: @schedule_semester)
        section = if grade.section_id
                    grade.section
                  elsif offering
                    offering.sections.order(:section_number).first
                  end
        { grade: grade, offering: offering, section: section }
      end
    end
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
      :program_id, :old_program, :admission_year_be, :status, :graduation_year_be,
      :tcas, :status_note, :remark
    )
  end
end
