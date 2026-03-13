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
    redirect_to(@data_import) and return unless @data_import.state == "pending"

    importer_class = @data_import.importer_class

    @data_import.file.open do |tempfile|
      spreadsheet = open_spreadsheet_from(tempfile, @data_import.file.filename.to_s)

      @sheets = spreadsheet.sheets
      @selected_sheet = params[:sheet].presence || @sheets.first
      @show_sheet_selector = @sheets.size > 1
      spreadsheet.default_sheet = @selected_sheet if @selected_sheet

      raw_headers = spreadsheet.row(1).map { |h| h.to_s.strip }
      @preview_row = spreadsheet.last_row >= 2 ? spreadsheet.row(2) : []
      @file_headers = importer_class.label_headers(raw_headers)
    end

    if @file_headers.blank?
      redirect_to new_data_import_path, alert: "File has no headers."
      return
    end

    @attribute_definitions = importer_class.attribute_definitions
    @auto_mapping = importer_class.auto_map(@file_headers.map { |h| h.sub(/\A[A-Z]+: /, "") })
  end

  CONSTANT_MARKER = "__constant__"

  def execute
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state == "pending"

    importer_class = @data_import.importer_class
    permitted_attrs = importer_class.attribute_definitions.map { |d| d[:attribute].to_s }

    raw_mapping = params.require(:mapping).permit(*permitted_attrs).to_h
    raw_defaults = params.fetch(:defaults, {}).permit(*permitted_attrs).to_h

    # Split into column mappings vs constant values
    column_mapping = {}
    default_values = {}
    raw_mapping.each do |attr, value|
      if value == CONSTANT_MARKER
        default_values[attr] = raw_defaults[attr] if raw_defaults[attr].present?
      elsif value.present?
        column_mapping[attr] = value
      end
    end

    # Validate required attributes are satisfied (by column mapping OR constant)
    satisfied = column_mapping.keys + default_values.keys
    missing = permitted_attrs.select { |a| importer_class.required_attributes.include?(a.to_sym) } - satisfied
    if missing.any?
      labels = importer_class.attribute_labels
      missing_labels = missing.map { |a| labels[a.to_sym] || a }
      redirect_to mapping_data_import_path(@data_import, sheet: params[:sheet_name]),
                  alert: "Required fields not mapped: #{missing_labels.join(', ')}"
      return
    end

    @data_import.update!(
      sheet_name: params[:sheet_name].presence,
      column_mapping: column_mapping,
      default_values: default_values.presence
    )
    importer = importer_class.new(@data_import)
    importer.call
    redirect_to @data_import, notice: "Import completed."
  end

  def retry_import
    @data_import = DataImport.find(params[:id])
    redirect_to(@data_import) and return unless @data_import.state == "failed"

    @data_import.update!(
      state: "pending",
      total_rows: 0,
      created_count: 0,
      updated_count: 0,
      error_count: 0,
      row_errors: nil,
      error_message: nil
    )
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
    else raise "Unsupported file format"
    end
  end
end
