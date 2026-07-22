# LINE renders plain text only — Markdown syntax reaches users as literal
# characters. The system prompt forbids Markdown, but instruction-following
# is probabilistic (qwen kept emitting **bold** after the 2026-07-22 prompt
# change), so this scrubber deterministically strips the residue from
# LINE-bound replies. Conservative by design: only unambiguous Markdown is
# touched; single *asterisks* are left alone (math like 3*4, star ratings).
module Line::MarkdownScrubber
  module_function

  def scrub(text)
    return text if text.blank?

    out = text.dup
    # Fenced code blocks: drop the fence lines, keep the content.
    out.gsub!(/^```[^\n]*\n?/, "")
    # Bold / underline emphasis pairs: **text** / __text__ → text.
    out.gsub!(/\*\*(.+?)\*\*/m, '\1')
    out.gsub!(/__(.+?)__/m, '\1')
    # Inline code: `text` → text.
    out.gsub!(/`([^`\n]+)`/, '\1')
    # ATX headers at line start: "## Title" → "Title".
    out.gsub!(/^\#{1,6}\s+/, "")
    # Links: [text](url) → text (url).
    out.gsub!(/\[([^\]\n]+)\]\(([^)\n]+)\)/, '\1 (\2)')
    out
  end
end
