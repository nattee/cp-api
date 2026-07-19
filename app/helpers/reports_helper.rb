module ReportsHelper
  # Resolves a catalog entry to its URL. Registry reports go through the generic
  # ReportsController#show (report_path/:id); external reports use their own
  # route helper (e.g. schedules_room_path, distribution_grades_path).
  def catalog_report_path(entry)
    entry.path_helper ? public_send(entry.path_helper) : report_path(entry.key)
  end
end
