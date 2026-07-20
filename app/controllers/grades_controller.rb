class GradesController < ApplicationController
  before_action :set_grade, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]
  before_action :require_manual_source, only: %i[edit update]

  # Grade-distribution report.
  LETTER_GRADES  = %w[A B+ B C+ C D+ D F].freeze  # GPA grades, in column order
  PASS_GRADES    = %w[A B+ B C+ C].freeze         # "C or higher" for the pass-rate column
  CHART_LINE_CAP = 10                             # max subjects plotted as GPA-trend lines

  def index
    if params[:year].present? && params[:semester].present?
      @grades = Grade.includes(:student, :course)
                     .for_term(params[:year], params[:semester])
      @filtered = true
    else
      @filtered = false
    end
    @available_years = Grade.distinct.pluck(:year_ce).sort.reverse
  end

  # Grade-distribution report: a set of subjects (course_no prefix) × term, with
  # the grade spread across columns. A GPA-trend line chart (x = term, one line
  # per subject) sits above the table — both driven by this one query. Rows
  # group by course_no (the cross-revision key), so a subject is one logical
  # series regardless of curriculum revision.
  def distribution
    @prefix = params.key?(:prefix) ? params[:prefix].to_s.strip : "2110"
    @program_code = params[:program_code].presence
    @split = params[:split] != "0" # split rows by semester (default on)

    @available_years = Grade.distinct.pluck(:year_ce).compact.sort
    @start_year = (params[:start_year].presence || @available_years.first).to_i
    @end_year   = (params[:end_year].presence   || @available_years.last).to_i
    @start_year, @end_year = @end_year, @start_year if @start_year > @end_year

    @program_groups = ProgramGroup.order(:code).pluck(:code)

    counts = grade_counts # { [course_no, year, semester, grade] => n }
    @titles = course_titles

    build_distribution_rows(counts)

    respond_to do |format|
      format.html do
        @course_ids = course_latest_ids
        build_gpa_trend(counts)
      end
      format.csv do
        exporter = Exporters::GradeDistributionExporter.new(rows: @rows, split: @split)
        send_data exporter.to_csv, filename: exporter.filename,
                  type: "text/csv", disposition: "attachment"
      end
    end
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
    redirect_to grades_path(year: @grade.year_ce, semester: @grade.semester),
                notice: "Grade was successfully deleted."
  end

  private

  # Letter-grade counts grouped by subject + term, honoring the report filters.
  def grade_counts
    base = @program_code ? Grade.joins(course: { programs: :program_group }) : Grade.joins(:course)
    base = base.where.not(grade: [nil, ""])
    base = base.where("courses.course_no LIKE ?", "#{@prefix}%") if @prefix.present?
    base = base.where(grades: { year_ce: @start_year..@end_year })
    base = base.where(program_groups: { code: @program_code }) if @program_code
    base.group("courses.course_no", "grades.year_ce", "grades.semester", "grades.grade").count("DISTINCT grades.id")
  end

  # course_no => most recent revision's name (later revisions overwrite earlier).
  def course_titles
    matching_courses.order(:revision_year_be).pluck(:course_no, :name).to_h
  end

  # course_no => id of its most recent revision (for linking to the course page).
  def course_latest_ids
    matching_courses.order(:revision_year_be).pluck(:course_no, :id).to_h
  end

  def matching_courses
    scope = Course.all
    scope = scope.where("course_no LIKE ?", "#{@prefix}%") if @prefix.present?
    scope = scope.where(id: Course.joins(programs: :program_group).where(program_groups: { code: @program_code }).select(:id)) if @program_code
    scope
  end

  # @rows: one hash per (subject[, term]); @terms: sorted [year, semester] pairs.
  def build_distribution_rows(counts)
    @terms = counts.keys.map { |_cn, y, s, _g| [y, s] }.uniq.sort

    grouped = Hash.new { |h, k| h[k] = Hash.new(0) }
    counts.each do |(course_no, year, semester, grade), n|
      key = @split ? [course_no, [year, semester]] : [course_no, nil]
      grouped[key][grade] += n
    end

    @rows = grouped.map { |(course_no, term), grade_counts| distribution_row(course_no, term, grade_counts) }
    @rows.sort_by! { |r| [r[:course_no], r[:term_key] || [0, 0]] }
  end

  def distribution_row(course_no, term, grade_counts)
    display = LETTER_GRADES + %w[W]
    graded_n = LETTER_GRADES.sum { |g| grade_counts[g] }
    weighted = LETTER_GRADES.sum { |g| grade_counts[g] * Grade::GRADE_WEIGHTS[g] }
    pass_n   = PASS_GRADES.sum { |g| grade_counts[g] }

    {
      course_no: course_no,
      title: @titles[course_no],
      term_key: term,
      term: term && "#{term[0]}/#{term[1]}",
      buckets: display.index_with { |g| grade_counts[g] },
      other: grade_counts.sum { |g, n| display.include?(g) ? 0 : n },
      n: grade_counts.values.sum,
      gpa: graded_n.positive? ? (weighted / graded_n.to_f).round(2) : nil,
      pass_rate: graded_n.positive? ? (pass_n.to_f / graded_n * 100).round : nil
    }
  end

  # @gpa_trend_data: Chart.js line data (labels = terms, one dataset per subject,
  # GPA per term or nil where not offered). Capped at the most-enrolled subjects.
  def build_gpa_trend(counts)
    agg = Hash.new { |h, k| h[k] = { weighted: 0.0, graded: 0, total: 0 } }
    counts.each do |(course_no, year, semester, grade), n|
      cell = agg[[course_no, [year, semester]]]
      cell[:total] += n
      if (weight = Grade::GRADE_WEIGHTS[grade])
        cell[:weighted] += weight * n
        cell[:graded] += n
      end
    end

    totals = Hash.new(0)
    agg.each { |(course_no, _term), cell| totals[course_no] += cell[:total] }

    ranked = totals.keys.sort_by { |course_no| -totals[course_no] }
    @trend_total = ranked.size
    chosen = ranked.first(CHART_LINE_CAP)
    @trend_truncated = ranked.size > chosen.size

    datasets = chosen.map do |course_no|
      data = @terms.map do |year, semester|
        cell = agg[[course_no, [year, semester]]]
        cell[:graded].positive? ? (cell[:weighted] / cell[:graded]).round(2) : nil
      end
      { label: course_no, data: data }
    end

    @gpa_trend_data = { labels: @terms.map { |y, s| "#{y}/#{s}" }, datasets: datasets }
  end

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
      :student_id, :course_id, :year_ce, :semester, :grade, :grade_weight, :credits_grant
    )
  end
end
