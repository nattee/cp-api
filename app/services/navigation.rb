# Single source of truth for the entity and tool areas listed on the home
# launchpad (app/views/home/index.html.haml).
#
# The sidebar in app/views/layouts/application.html.haml lists the same
# destinations but is NOT driven from here, deliberately: it renders live badge
# counts (LineContact.count, ApiEvent.errors_since) and matches active state
# across multiple controllers (%w[program_groups programs]). Encoding that here
# would mean lambdas and controller-arrays for the benefit of one caller. The
# duplication is guarded by test/integration/navigation_parity_test.rb, which
# fails if a sidebar destination is missing from home.
#
# Reports are NOT listed here — they come from Reports::Catalog.
module Navigation
  # :key         — ApplicationHelper::RESOURCE_ICONS key, for resource_icon
  # :path_helper — zero-argument route helper, resolved with public_send
  # :group       — which band on home: :records, :teaching_setup, :admin, :account
  # :access      — a Permission::CATALOG key, or nil for everyone
  AREAS = [
    # --- Records: the "look something up" destinations ---
    { key: "program_groups", label: "Programs", group: :records, access: "courses.read",
      path_helper: :program_groups_path,
      description: "Curricula and their revisions, with course requirements." }.freeze,
    { key: "courses", label: "Courses", group: :records, access: "courses.read",
      path_helper: :courses_path,
      description: "Course catalogue across curriculum revisions." }.freeze,
    { key: "staffs", label: "Staff", group: :records, access: "courses.read",
      path_helper: :staffs_path,
      description: "Lecturers and their teaching assignments." }.freeze,
    { key: "students", label: "Students", group: :records, access: "students.read_minimal",
      path_helper: :students_path,
      description: "Student records, transcripts and course history." }.freeze,
    { key: "grades", label: "Grades", group: :records, access: "grades.read",
      path_helper: :grades_path,
      description: "Enrolment and grade rows by term." }.freeze,

    # --- Teaching setup: the data the schedule reports read from ---
    { key: "semesters", label: "Semesters", group: :teaching_setup, access: "courses.read",
      path_helper: :semesters_path,
      description: "Terms, course offerings, sections and time slots." }.freeze,
    { key: "rooms", label: "Rooms", group: :teaching_setup, access: "courses.read",
      path_helper: :rooms_path,
      description: "Teaching rooms and their capacity." }.freeze,
    { key: "scrapes", label: "Scraper", group: :teaching_setup, access: "users.manage",
      path_helper: :scrapes_path,
      description: "Pull schedule data from the registrar's site." }.freeze,

    # --- Administration: system operation, admin-only ---
    { key: "users", label: "Users", group: :admin, access: "users.manage",
      path_helper: :users_path,
      description: "Accounts, roles and LLM settings." }.freeze,
    { key: "data_imports", label: "Imports", group: :admin, access: "users.manage",
      path_helper: :data_imports_path,
      description: "CSV and Excel uploads, with column mapping." }.freeze,
    { key: "data_sources", label: "Data Sources", group: :admin, access: "users.manage",
      path_helper: :data_sources_path,
      description: "Where each kind of data comes from, and how complete it is." }.freeze,
    { key: "api_events", label: "API Events", group: :admin, access: "users.manage",
      path_helper: :api_events_path,
      description: "External API calls and their failures." }.freeze,
    { key: "chats", label: "Chat Playground", group: :admin, access: "users.manage",
      path_helper: :chat_path,
      description: "Try the assistant against live data." }.freeze,
    { key: "chat_messages", label: "Chat History", group: :admin, access: "users.manage",
      path_helper: :chat_messages_path,
      description: "Past assistant conversations and their tool calls." }.freeze,
    { key: "line_contacts", label: "LINE Contacts", group: :admin, access: "users.manage",
      path_helper: :line_contacts_path,
      description: "Unlinked LINE users waiting for an account." }.freeze,
    { key: "dev", label: "Style Guide", group: :admin, access: "users.manage",
      path_helper: :dev_styleguide_path,
      description: "Colour playground and component reference." }.freeze,

    # --- Your account: personal settings, not domain data ---
    { key: "line_accounts", label: "LINE Account", group: :account, access: nil,
      path_helper: :line_account_path,
      description: "Link your LINE account so the bot can answer as you." }.freeze
  ].freeze

  module_function

  def for_group(group)
    AREAS.select { |a| a[:group] == group }
  end

  def visible_to(areas, user:)
    areas.select { |a| a[:access].nil? || user.can?(a[:access]) }
  end
end
