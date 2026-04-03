# LINE Integration

## Architecture

```
LINE Platform --POST--> /line/webhook (reverse proxy) --> WebhookController (ActionController::API)
  --> verify X-Line-Signature (HMAC-SHA256)
  --> enqueue EventDispatchJob (solid_queue)
  --> return 200 OK immediately

EventDispatchJob --> EventRouter --> MessageRouter --> Command handler
  --> Command checks user is linked (provider="line", uid=LINE userId)
  --> Calls ReplyService to reply via LINE API
```

## File Map

| File | Purpose |
|---|---|
| `config/initializers/line_bot.rb` | Singleton client + channel_secret from credentials |
| `app/controllers/line/webhook_controller.rb` | Receives LINE events, verifies signature, enqueues job |
| `app/controllers/line_accounts_controller.rb` | Web UI for linking/unlinking LINE account |
| `app/jobs/line/event_dispatch_job.rb` | Processes LINE events via solid_queue |
| `app/services/line/event_router.rb` | Routes by event type (message, follow) |
| `app/services/line/message_router.rb` | Parses text, resolves command from COMMAND_MAP |
| `app/services/line/reply_service.rb` | Wrapper around LINE SDK reply API |
| `app/services/line/commands/base_command.rb` | Shared: current_user, linked?, require_linked!, reply |
| `app/services/line/commands/link_command.rb` | `link <token>` — links LINE account to system user |
| `app/services/line/commands/help_command.rb` | Lists available commands |
| `app/services/line/commands/unknown_command.rb` | Fallback for unrecognized input |
| `app/views/line_accounts/show.html.haml` | Linking status, generate-token button, unlink button |

## Credentials

Stored in Rails encrypted credentials (`bin/rails credentials:edit`):

```yaml
line:
  channel_secret: "..."
  channel_access_token: "..."
```

## Account Linking Flow

1. User logs into CP-API, visits `/line_account`, clicks "Generate Linking Code"
2. System saves a random token + 30-min expiry on the user record
3. User sends `link <token>` to the LINE bot
4. LinkCommand looks up token, verifies expiry, sets `provider="line"` + `uid=<LINE userId>`, clears token
5. Bot replies "Linked successfully"

## Adding Commands

1. Create `app/services/line/commands/your_command.rb` extending `BaseCommand`
2. Add entry to `COMMAND_MAP` in `app/services/line/message_router.rb`

## Dev Setup (LINE webhook via SSH tunnel)

1. Open SSH reverse tunnel to the proxy machine:
   ```
   ssh -R 3000:localhost:3000 10.44.0.2
   ```
2. Zoraxy rule: `cp-line.nattee.net` → `http://localhost:3000`
3. LINE Console webhook URL: `https://cp-line.nattee.net/line/webhook`
4. `config/environments/development.rb` has `cp-line.nattee.net` in allowed hosts for this to work

## Production

Change Zoraxy target from `localhost:3000` to `10.0.5.59:3000` (or wherever the production server is) and drop the SSH tunnel.

# Tool Calling System Design

## Overview
LINE chatbot uses vLLM (OpenAI-compatible API) with tool calling to handle
natural-language queries about students, courses, staff, and schedules.

## Architecture
- WebhookController receives LINE webhook, enqueues ChatJob
- ChatJob calls LlmService which runs the tool-calling loop
- LlmService sends messages + tool definitions to vLLM
- When vLLM returns tool_calls, ToolExecutor dispatches to handler classes
- Results are sent back to vLLM for the next round
- Loop ends when vLLM returns plain text (max 5 rounds)
- Reply via reply_token, fallback to push_message if expired

## Key classes
- `LlmService` — manages conversation loop with vLLM
- `ToolRegistry` — maps tool names to definitions + handlers
- `ToolExecutor` — dispatches tool calls, wraps errors
- `ChatJob` — ActiveJob that ties it all together

## vLLM endpoint
- Config: `config/llm.yml` — base URL, endpoint, model name per environment
- Endpoint: `POST /v1/chat/completions` (OpenAI-compatible format with `tools` parameter)
- Multiple model backends supported; users select via `/model` command

## LINE integration
- Reply token expires ~30s, fallback to push API
- Pass both reply_token and user_id to ChatJob

## Tool Design Principles

Tools are organized by **domain entity**, not by individual query type. The LLM
selects tools and fills parameters based on the user's natural language — no
intent classification code is needed on our side.

Keep the total tool count low (aim for ~5) to maintain LLM selection accuracy.
Each tool accepts **flexible optional parameters** so one tool covers many
intents. The LLM can chain tools across rounds (up to `max_rounds`).

### Tool inventory

| Tool | Purpose | Example queries |
|---|---|---|
| `student_lookup` | Find students by ID/name/program/year/status. Returns profile, GPA, credits. | "ขอข้อมูล 6530200321", "หานิสิตชื่อสมชาย", "how many 2nd year CP students?" |
| `course_lookup` | Find courses by course_no/name/program. Returns course info + who teaches it. | "who teaches Algorithm Design?", "courses in CP curriculum" |
| `staff_lookup` | Find staff by name/initials. Returns staff info + current teaching assignments. | "what does อ.ณัฐ teach?", "staff NNN" |
| `schedule_lookup` | Query sections/time slots for a semester — by course, staff, or room. | "what room is 2110327 in?", "Tuesday schedule for ENG 305" |
| `grade_summary` | Aggregate queries: grade distribution, pass rates, program statistics. | "grade distribution for 2110327", "average GPA of CP 65" |

### Tool parameter pattern

Each tool uses a single `query` string for free-text search plus **optional
typed filters** for structured narrowing. Example for `student_lookup`:

```
query:          "name or student ID" (optional)
program_code:   "CP", "CEDT", etc. (optional)
admission_year: Buddhist Era year (optional)
status:         "active" / "graduated" / "on_leave" / "retired" (optional)
limit:          max results, default 10 (optional)
```

The LLM maps natural language to parameters:
- "how many active 2nd year CP students?" → `student_lookup(program_code: "CP", admission_year: 2568, status: "active")`
- "who is 6530200321?" → `student_lookup(query: "6530200321")`

### Adding a new tool

1. Create `app/services/line/tools/your_tool.rb` with a `DEFINITION` constant and `self.call(arguments)` method
2. Register in the initializer: `Line::ToolRegistry.register("your_tool", definition: YourTool::DEFINITION, handler: YourTool)`
3. Keep the description precise — it's what the LLM uses for selection

