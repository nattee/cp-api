module ApiEventsHelper
  # Renders API event details as a readable, expandable structure.
  #
  # The details JSON often contains nested JSON strings — e.g. request_body
  # and response_body are JSON-encoded strings stored inside the outer JSON.
  # A plain JSON.pretty_generate shows these as escaped one-liners:
  #
  #   "request_body": "{\"model\":\"glm-5\",\"messages\":[...]}"
  #
  # This helper detects JSON string values and renders them as collapsible
  # sections with properly formatted JSON inside, making it easy to inspect
  # the actual request/response payloads.
  def render_api_event_details(details)
    # Separate large JSON string fields (request/response bodies) from
    # simple scalar fields for different rendering treatment.
    simple = {}
    json_fields = {}

    details.each do |key, value|
      if value.is_a?(String) && value.start_with?("{", "[") && value.length > 100
        parsed = JSON.parse(value) rescue nil
        if parsed
          json_fields[key] = parsed
        else
          simple[key] = value
        end
      else
        simple[key] = value
      end
    end

    # Build the HTML output.
    parts = []

    # Simple fields as a compact JSON block.
    if simple.any?
      parts << content_tag(:pre, JSON.pretty_generate(simple), class: "mt-1 mb-1 small")
    end

    # Nested JSON fields as collapsible sections with formatted content.
    json_fields.each do |key, parsed|
      parts << content_tag(:details, class: "mt-1") do
        summary = content_tag(:summary, class: "text-body-secondary small fw-semibold") { key.to_s }
        body = content_tag(:pre, JSON.pretty_generate(parsed), class: "mt-1 mb-1 small", style: "max-height: 400px; overflow-y: auto;")
        summary + body
      end
    end

    safe_join(parts)
  end
end
