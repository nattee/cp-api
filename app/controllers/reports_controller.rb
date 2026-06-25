class ReportsController < ApplicationController
  before_action :require_admin

  # Dashboard: per-program menu of reports, grouped by section.
  def index
    @program_groups = ProgramGroup.order(:code)
    @selected_group = @program_groups.find_by(code: params[:program_group]) if params[:program_group].present?
    reports = @selected_group ? Reports::Registry.for_program(@selected_group) : Reports::Registry.all
    @reports_by_section = Reports::Registry.grouped(reports)
  end

  # One report: render its param form, and (when run) its result table / CSV.
  def show
    @report = Reports::Registry.find(params[:id])
    return redirect_to(reports_path, alert: "Unknown report.") unless @report

    if params[:run].present?
      missing = @report.params_spec.select { |p| p[:required] && params[p[:name]].blank? }
      if missing.any?
        flash.now[:alert] = "Please fill in: #{missing.map { |p| p[:name].to_s.humanize }.join(', ')}"
      else
        @result = @report.new(report_params).run
      end
    end

    respond_to do |format|
      format.html
      format.csv do
        @result ||= @report.new(report_params).run
        exporter = Exporters::ReportExporter.new(@result, filename: @report.key)
        send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
      end
    end
  end

  private

  # Whitelist: only the report's declared params, by name.
  def report_params
    @report.params_spec.each_with_object({}) { |p, h| h[p[:name].to_s] = params[p[:name]] }
  end

  def require_admin
    redirect_to root_path, alert: "Only admins can view reports." unless current_user.admin?
  end
end
