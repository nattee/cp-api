# Tool Chain Audit & Inspector

## Problem

The LLM tool-calling loop in `Line::LlmService` is opaque after execution:
- **`ApiEvent`** logs vLLM HTTP calls (timing, status) but not which tools were called or what they returned.
- **`ChatMessage`** only persists the final user/assistant pair — intermediate tool-calling rounds are discarded (line 58–59 of `llm_service.rb`).
- An admin can see the final answer but cannot reconstruct *how* the LLM arrived at it.

This makes it impossible to audit whether the model selected appropriate tools, passed correct parameters, or interpreted results correctly.

## Goals

1. Super admins can audit every tool call (name, arguments, result) for any conversation.
2. Selected users can see the full tool chain in the chat history UI instead of just the final response.
3. Tool execution is logged as filterable events in `/api_events`.
4. The chat history UI renders the tool chain as a readable visual timeline.

## Implementation Plan

### A. Persist full tool chain in `ChatMessage`

**What changes**: Remove the "tool-calling rounds are not saved" design decision. Save every intermediate message during the tool-calling loop.

**File**: `app/services/line/llm_service.rb`

After `Line::ToolExecutor.execute(tool_calls)` returns, save:
1. The assistant message with its `tool_calls` JSON.
2. Each tool result message with `role: "tool"`, `content`, and `tool_call_id`.

```ruby
# Save assistant's tool-call message (no text content, just tool_calls)
save_message(role: "assistant", content: assistant_message["content"], tool_calls: tool_calls)

# Save each tool result
tool_results.each do |tr|
  save_message(role: "tool", content: tr[:content], tool_call_id: tr[:tool_call_id])
end
```

These intermediate messages are also appended to `messages` for the next round (already happening). The `build_initial_messages` path via `ChatMessage.recent_for` and `to_llm_message` already handles `tool_calls` and `tool_call_id` fields, so future conversations that load history will correctly include tool-calling context.

**Impact on history limit**: The 20-message `HISTORY_LIMIT` now includes tool-call rounds. A single user request that triggers 3 tool calls produces 7 messages (user + 3x assistant-tool-call + 3x tool-result + final assistant). Consider bumping `HISTORY_LIMIT` to 40, or counting only `user`/`assistant`-with-content messages toward the limit.

### B. Add `debug_tool_calls` flag to User

**Migration**: Add `debug_tool_calls` boolean (default `false`) to `users` table.

**User form**: Add a checkbox in the user edit form, visible only to super admins. This controls whether the user sees tool chain details when viewing chat history.

**Controller**: In `ChatMessagesController#show`, set `@debug_mode = current_user.debug_tool_calls?`.

**View logic**: The show view currently does `next if msg.role == "tool"`. Change to:
```haml
- next if msg.role == "tool" && !@debug_mode
```

Assistant-messages that have `tool_calls` but no text content (pure tool-call requests) are also hidden unless debug mode is on.

### C. Log tool execution to `ApiEvent`

**File**: `app/services/line/tool_executor.rb`

Wrap each tool invocation with `ApiEvent.log`:

```ruby
def self.invoke(name, raw_args)
  handler = Line::ToolRegistry.handler_for(name)
  unless handler
    ApiEvent.log(service: "llm", action: "tool_call", severity: "warning",
                 message: "Unknown tool: #{name}", details: { tool: name, arguments: raw_args })
    return "Error: unknown tool '#{name}'"
  end

  arguments = raw_args.is_a?(String) ? JSON.parse(raw_args) : raw_args
  result = handler.call(arguments)

  ApiEvent.log(service: "llm", action: "tool_call", severity: "info",
               message: "Tool: #{name}", details: { tool: name, arguments: arguments, result: result.to_s.truncate(500) })
  result
rescue JSON::ParserError => e
  # ... existing error handling, plus ApiEvent.log with severity: "error"
rescue => e
  ApiEvent.log(service: "llm", action: "tool_call", severity: "error",
               message: "Tool failed: #{name}", details: { tool: name, arguments: raw_args, error: e.message })
  # ... existing error handling
end
```

This makes tool calls visible in the existing `/api_events` UI with service filter "LLM" and action "tool_call".

### D. Tool Chain Inspector UI

**Where**: `app/views/chat_messages/show.html.haml`

When `@debug_mode` is true, render the full message sequence as a visual timeline instead of just user/assistant bubbles. The timeline shows:

1. **User message** — existing chat bubble style.
2. **Tool-call step** — a compact card with wrench icon, showing tool name and arguments in a collapsible `<details>` block. Styled distinctly (e.g. dashed border, muted background) to differentiate from conversation messages.
3. **Tool result** — the returned data in a `<pre>` code block, collapsible, nested under the tool-call step.
4. **Repeat** steps 2–3 for each tool call in each round, and for each round.
5. **Final assistant message** — existing chat bubble style.

**Visual design**:
- Tool-call steps use a vertical timeline connector (thin left border line) to show they're intermediate steps between user and final answer.
- Each round is visually grouped (e.g. "Round 1", "Round 2" label if multiple rounds occurred).
- Tool name is shown as a badge, arguments as collapsible JSON, result as collapsible preformatted text.
- Round labels only appear when there are 2+ rounds.

**CSS classes** (in `application.scss`):
- `.chat-tool-step` — the tool-call card (dashed border, subtle background)
- `.chat-tool-result` — the result block (code-style)
- `.chat-tool-chain` — wrapper with left-border timeline connector

**Non-debug mode**: Unchanged — `tool` messages and content-less assistant messages are skipped, user sees clean conversation.

## Files Changed

| File | Change |
|------|--------|
| `app/services/line/llm_service.rb` | Save intermediate tool-call and tool-result messages |
| `app/services/line/tool_executor.rb` | Add `ApiEvent.log` for each tool invocation |
| `db/migrate/*_add_debug_tool_calls_to_users.rb` | New migration |
| `app/models/user.rb` | Add attribute |
| `app/views/users/_form.html.haml` | Add checkbox |
| `app/controllers/chat_messages_controller.rb` | Set `@debug_mode` |
| `app/views/chat_messages/show.html.haml` | Tool chain inspector UI |
| `app/assets/stylesheets/application.scss` | Timeline/tool-step styles |

## Future Considerations

- **Feedback buttons**: Thumbs-up/down on individual tool calls for evaluation data.
- **Tool metrics dashboard**: Aggregate tool_call events — frequency, latency, error rate, per-model comparison.
- **Dry-run mode**: Mock tool results for testing tool selection without side effects.
- **History limit**: May need to bump `HISTORY_LIMIT` or change counting strategy since tool-call rounds now consume message slots.
