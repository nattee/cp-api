class DataImportsController < ApplicationController
  before_action :require_admin

  def index
    @data_imports = DataImport.includes(:user).order(created_at: :desc)
  end

  def show
    @data_import = DataImport.find(params[:id])
  end

  def new
    @data_import = DataImport.new
  end

  def create
    @data_import = DataImport.new(data_import_params)
    @data_import.user = current_user
    @data_import.state = "pending"

    if @data_import.save
      redirect_to mapping_data_import_path(@data_import)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def mapping
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state.in?(%w[pending retrying])

    importer_class = @data_import.importer_class
    @configured_sheets = @data_import.sheet_configs || []

    begin
      @data_import.file.open do |tempfile|
        spreadsheet = open_spreadsheet_from(tempfile, @data_import.file.filename.to_s)

        @sheets = spreadsheet.sheets
        @show_sheet_selector = @sheets.size > 1
        configured_names = @configured_sheets.map { |c| c["sheet_name"] }
        @available_sheets = @sheets - configured_names

        @selected_sheet = if params[:sheet].present? && @sheets.include?(params[:sheet])
                            params[:sheet]
                          elsif @available_sheets.any?
                            @available_sheets.first
                          else
                            @sheets.first
                          end

        spreadsheet.default_sheet = @selected_sheet if @selected_sheet

        raw_headers = spreadsheet.row(1).map { |h| h.to_s.strip }
        @preview_row = spreadsheet.last_row >= 2 ? spreadsheet.row(2) : []
        @file_headers = importer_class.label_headers(raw_headers)
      end
    rescue Zip::Error, Ole::Storage::FormatError, CSV::MalformedCSVError, ArgumentError => e
      redirect_to new_data_import_path, alert: "Could not read the uploaded file. Please check that it is a valid .csv or .xlsx file."
      return
    end

    if @file_headers.blank?
      redirect_to new_data_import_path, alert: "File has no headers."
      return
    end

    @attribute_definitions = importer_class.attribute_definitions
    @derivable_attributes = importer_class.derivable_attributes
    @auto_mapping = importer_class.auto_map(@file_headers.map { |h| h.sub(/\A[A-Z]+: /, "") })

    # Pre-fill from saved config when editing an already-configured sheet
    existing_config = @configured_sheets.find { |c| c["sheet_name"] == @selected_sheet }
    if existing_config
      @editing_sheet = true
      @saved_mapping = existing_config["column_mapping"] || {}
      @saved_defaults = existing_config["default_values"] || {}
    else
      @editing_sheet = false
    end
  end

  CONSTANT_MARKER = "__constant__"
  PROGRAM_GROUP_MARKER = "__program_group__"

  # Save current sheet's column mapping and add another sheet
  def save_sheet
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state.in?(%w[pending retrying])

    config = build_sheet_config
    return if config.nil? # redirected with error

    configs = @data_import.sheet_configs || []
    # Replace if same sheet already configured, otherwise append
    configs.reject! { |c| c["sheet_name"] == config["sheet_name"] }
    configs << config

    @data_import.update!(sheet_configs: configs)
    redirect_to mapping_data_import_path(@data_import), notice: "Sheet \"#{config['sheet_name']}\" configured. Select the next sheet to configure."
  end

  # Remove a configured sheet
  def remove_sheet
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state.in?(%w[pending retrying])

    sheet_name = params[:sheet_name]
    configs = (@data_import.sheet_configs || []).reject { |c| c["sheet_name"] == sheet_name }
    @data_import.update!(sheet_configs: configs.presence)
    redirect_to mapping_data_import_path(@data_import), notice: "Sheet \"#{sheet_name}\" removed."
  end

  def execute
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state.in?(%w[pending retrying])

    configs = @data_import.sheet_configs || []

    # Only build a sheet config if the mapping form was submitted
    if params[:mapping].present?
      config = build_sheet_config
      return if config.nil? # redirected with error

      configs.reject! { |c| c["sheet_name"] == config["sheet_name"] }
      configs << config
    end

    if configs.empty?
      redirect_to mapping_data_import_path(@data_import), alert: "No sheets configured. Please configure at least one sheet."
      return
    end

    # For single-sheet files (CSV), also write legacy columns for backward compat
    first = configs.first
    @data_import.update!(
      sheet_configs: configs,
      sheet_name: first["sheet_name"],
      column_mapping: first["column_mapping"],
      default_values: first["default_values"],
      skip_failures: params[:skip_failures] == "1"
    )

    importer = @data_import.importer_class.new(@data_import)
    importer.call
    redirect_to @data_import, notice: "Import completed."
  end

  def retry_import
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state.in?(%w[failed completed])

    reset_attrs = {
      state: "retrying",
      row_errors: nil,
      error_message: nil,
      skip_failures: false,
      total_rows: 0,
      created_count: 0,
      updated_count: 0,
      unchanged_count: 0,
      skipped_count: 0,
      error_count: 0
    }

    # Preserve sheet configs but strip per-sheet result data
    if @data_import.sheet_configs.present?
      result_keys = %w[total_rows created_count updated_count unchanged_count skipped_count error_count row_errors]
      reset_attrs[:sheet_configs] = @data_import.sheet_configs.map { |c| c.except(*result_keys) }
    end

    @data_import.update!(reset_attrs)
    redirect_to mapping_data_import_path(@data_import)
  end

  private

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can access imports."
    end
  end

  def data_import_params
    params.require(:data_import).permit(:target_type, :mode, :file)
  end

  def open_spreadsheet_from(tempfile, filename)
    case File.extname(filename).downcase
    when ".xlsx" then Roo::Excelx.new(tempfile.path)
    when ".xls"  then Roo::Excel.new(tempfile.path)
    when ".csv"  then Roo::CSV.new(tempfile.path)
    else raise ArgumentError, "Unsupported file format: #{File.extname(filename)}"
    end
  end

  # Build a sheet config hash from form params. Returns nil and redirects if validation fails.
  def build_sheet_config
    importer_class = @data_import.importer_class
    permitted_attrs = importer_class.attribute_definitions.map { |d| d[:attribute].to_s }

    raw_mapping = params.require(:mapping).permit(*permitted_attrs).to_h
    raw_defaults = params.fetch(:defaults, {}).permit(*permitted_attrs).to_h

    column_mapping = {}
    default_values = {}
    raw_mapping.each do |attr, value|
      if value == CONSTANT_MARKER
        default_values[attr] = raw_defaults[attr] if raw_defaults[attr].present?
      elsif value == PROGRAM_GROUP_MARKER
        group_id = params.dig(:defaults, :_program_group_id)
        default_values["_program_group_id"] = group_id if group_id.present?
      elsif value.present?
        column_mapping[attr] = value
      end
    end

    # Validate required attributes
    satisfied = column_mapping.keys + default_values.keys
    derivable = importer_class.derivable_attributes.map(&:to_s)
    missing = permitted_attrs.select { |a| importer_class.required_attributes.include?(a.to_sym) } - satisfied - derivable
    if missing.any?
      labels = importer_class.attribute_labels
      missing_labels = missing.map { |a| labels[a.to_sym] || a }
      redirect_to mapping_data_import_path(@data_import, sheet: params[:sheet_name]),
                  alert: "Required fields not mapped: #{missing_labels.join(', ')}"
      return nil
    end

    # Include grade-specific blank_grade option in default_values
    if raw_defaults["_blank_grade"].present?
      default_values["_blank_grade"] = raw_defaults["_blank_grade"]
    end

    {
      "sheet_name" => params[:sheet_name].presence,
      "column_mapping" => column_mapping,
      "default_values" => default_values.presence
    }
  end
end
