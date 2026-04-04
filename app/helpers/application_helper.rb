module ApplicationHelper
  RESOURCE_ICONS = {
    "program_groups" => "account_tree",
    "programs"      => "description",
    "courses"       => "menu_book",
    "staffs"        => "groups",
    "students"      => "school",
    "grades"        => "grading",
    "users"         => "group",
    "line_accounts"  => "chat",
    "line_contacts"  => "person_search",
    "chat_messages"  => "forum",
    "data_imports"   => "upload_file",
    "api_events"     => "monitor_heart",
    "semesters"        => "calendar_month",
    "course_offerings" => "event_note",
    "rooms"            => "meeting_room",
    "scrapes"          => "cloud_sync",
    "schedules"        => "date_range",
    "dev"              => "palette",
  }.freeze

  def resource_icon(resource = controller_name)
    icon = RESOURCE_ICONS[resource]
    tag.span(icon, class: "material-symbols resource-icon me-2") if icon
  end
end
