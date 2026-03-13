module ApplicationHelper
  RESOURCE_ICONS = {
    "programs"      => "account_tree",
    "courses"       => "menu_book",
    "students"      => "school",
    "users"         => "group",
    "line_accounts" => "chat",
    "data_imports"  => "upload_file",
  }.freeze

  def resource_icon(resource = controller_name)
    icon = RESOURCE_ICONS[resource]
    tag.span(icon, class: "material-symbols resource-icon me-2") if icon
  end
end
