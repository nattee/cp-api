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
    "chats"          => "smart_toy",
    "reports"        => "query_stats",
    "line_contacts"  => "person_search",
    "chat_messages"  => "forum",
    "data_imports"   => "upload_file",
    "api_events"     => "monitor_heart",
    "semesters"        => "calendar_month",
    "course_offerings" => "event_note",
    "rooms"            => "meeting_room",
    "scrapes"          => "cloud_sync",
    "dev"              => "palette",
    "data_sources"     => "database",
    # "profile" is not a controller - it's the home launchpad's pseudo-resource
    # key for the current user's own account, kept distinct from "users" so it
    # doesn't share an icon with the Users admin card.
    "profile"          => "account_circle",
  }.freeze

  def resource_icon(resource = controller_name)
    icon = RESOURCE_ICONS[resource]
    tag.span(icon, class: "material-symbols resource-icon me-2") if icon
  end

  # Membership+type tokens for the shared course filter (see course_filter_controller.js).
  # One token per (course, program) pairing, "<program_code>-<TYPE>", e.g.
  # "4784-C 3736-ELEC". The program_code carries membership (Program filter) and
  # the TYPE bucket carries compulsory/elective (Type filter) — the two are kept
  # coupled per pairing so a course compulsory in one program and elective in
  # another is filtered correctly. Requires program_courses (and their programs)
  # eager-loaded, or this N+1s.
  def course_filter_tokens(course)
    course.program_courses.filter_map { |pc|
      "#{pc.program.program_code}-#{ProgramCourse.filter_type(pc.course_group_code)}" if pc.program
    }.uniq.join(" ")
  end
end
