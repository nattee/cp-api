class ReportsController < ApplicationController
  # Access is per-report (see Reports::Catalog), not a blanket controller gate:
  # every hub report is open to any logged-in lecturer; only :admin reports
  # (Data Coverage) are restricted.

  # Hub: lecturer-facing reports grouped by section, optional program filter.
  def index
    @program_groups = ProgramGroup.order(:code)
    @selected_group = @program_groups.find_by(code: params[:program_group]) if params[:program_group].present?
    entries = Reports::Catalog.hub_entries
    entries = entries.select { |e| e.applicable_to?(@selected_group) } if @selected_group
    @entries_by_section = Reports::Catalog.grouped(entries)
  end

  # One framework report: render its param form, and (when run) its result / CSV.
  def show
    entry = Reports::Catalog.find(params[:id])
    return redirect_to(reports_path, alert: "Unknown report.") unless entry
    # External reports render in their own controller — send the user to the real page.
    return redirect_to(public_send(entry.path_helper)) unless entry.registry?
    if entry.access == :admin && !current_user.admin?
      return redirect_to(root_path, alert: "Only admins can view that report.")
    end
    @report = entry.report_class

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
end
