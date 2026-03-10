module ApplicationHelper
  RESOURCE_ICONS = {
    "students"      => "school",
    "users"         => "group",
    "line_accounts" => "chat",
  }.freeze

  def resource_icon(resource = controller_name)
    icon = RESOURCE_ICONS[resource]
    tag.span(icon, class: "material-symbols resource-icon me-2") if icon
  end
end
