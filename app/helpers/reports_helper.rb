module ReportsHelper
  # Resolves a catalog entry to its URL. Registry reports go through the generic
  # ReportsController#show (report_path/:id); external reports use their own
  # route helper (e.g. schedules_room_path, distribution_grades_path).
  def catalog_report_path(entry)
    entry.path_helper ? public_send(entry.path_helper) : report_path(entry.key)
  end

  # The default value a context-opted param should pre-fill with, or nil when the
  # param does not opt into the sticky term. Keyed by the param's context: axis.
  def context_default_for(param)
    return nil unless param[:context]
    ctx = current_term_context
    case param[:context]
    when :year            then ctx.academic_year_be
    when :semester        then ctx.semester_number
    when :semester_record then ctx.semester_record&.id
    end
  end
end
