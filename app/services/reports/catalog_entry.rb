module Reports
  # One navigable report in the hub / sidebar, whether it renders through the
  # generic ReportsController framework (a "registry" report, report_class set)
  # or in its own controller (an "external" report, path_helper set).
  #
  # `access` is a permission-key String (e.g. "courses.read", "grades.read",
  # "users.manage") consumed by Catalog.hub_entries(user:) and
  # ReportsController#show via User#can?.
  CatalogEntry = Struct.new(
    :key, :title, :description, :section, :access, :path_helper, :report_class,
    keyword_init: true
  ) do
    def registry? = report_class.present?

    # System reports (e.g. Data Coverage) are admin operational checks, not
    # lecturer analytics — reachable by their route, never listed in the hub.
    def hub? = section != :system

    # External reports are program-agnostic; registry reports may be scoped
    # (e.g. Thesis Credits is master-only) via the report class.
    def applicable_to?(group) = registry? ? report_class.applicable_to?(group) : true
  end
end
