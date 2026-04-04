# LINE Integration

## Architecture

```
LINE Platform --POST--> /line/webhook (reverse proxy) --> WebhookController (ActionController::API)
  --> verify X-Line-Signature (HMAC-SHA256)
  --> enqueue EventDispatchJob (solid_queue)
  --> return 200 OK immediately

EventDispatchJob --> EventRouter --> MessageRouter
  --> If command (link, help, clear, model): dispatch to command handler
  --> If linked user with llm_consent: enqueue ChatJob for LLM processing
  --> If unlinked user: record LineContact, reply once "admin will set up your account"

ChatJob --> LlmService --> vLLM (OpenAI-compatible API)
  --> Tool-calling loop (max 5 rounds): LLM requests tools → ToolExecutor dispatches → results fed back
  --> Final text reply sent via ReplyService (reply_token, fallback to push)
  --> All messages (including tool rounds) persisted to ChatMessage
```

## File Map

| File | Purpose |
|---|---|
| **Webhook & routing** | |
| `config/initializers/line_bot.rb` | Singleton client + channel_secret from credentials |
| `app/controllers/line/webhook_controller.rb` | Receives LINE events, verifies signature, enqueues job |
| `app/jobs/line/event_dispatch_job.rb` | Processes LINE events via solid_queue |
| `app/services/line/event_router.rb` | Routes by event type (message, follow) |
| `app/services/line/message_router.rb` | Parses text, resolves command or dispatches to LLM |
| `app/services/line/reply_service.rb` | Wrapper around LINE SDK reply + push API |
| **Commands** | |
| `app/services/line/commands/base_command.rb` | Shared: current_user, linked?, reply |
| `app/services/line/commands/link_command.rb` | `link <token>` — links LINE account to system user |
| `app/services/line/commands/help_command.rb` | Lists available commands |
| `app/services/line/commands/clear_command.rb` | Clears conversation history |
| `app/services/line/commands/model_command.rb` | Show/switch LLM model preference |
| `app/services/line/commands/unknown_command.rb` | Fallback for unrecognized input |
| **LLM** | |
| `app/jobs/line/chat_job.rb` | Async job: calls LlmService, sends reply |
| `app/services/line/llm_service.rb` | Tool-calling loop with vLLM |
| `app/services/line/tool_executor.rb` | Dispatches tool calls to handlers, logs to ApiEvent |
| `app/services/line/tool_registry.rb` | Maps tool names to definitions + handler classes |
| `config/initializers/line_tools.rb` | Registers tools at boot |
| `config/llm.yml` | vLLM endpoints, models, system prompt |
| **Tools** | |
| `app/services/line/tools/echo_tool.rb` | Test tool — echoes arguments back |
| **Models** | |
| `app/models/chat_message.rb` | Conversation history (user, assistant, tool messages) |
| `app/models/line_contact.rb` | Unlinked LINE users awaiting admin onboarding |
| `app/models/api_event.rb` | Event log for LLM calls, tool executions, LINE API |
| **Web UI** | |
| `app/controllers/line_accounts_controller.rb` | User-facing: link/unlink own LINE account |
| `app/controllers/chat_messages_controller.rb` | Admin: view conversation history + tool chain inspector |
| `app/controllers/line_contacts_controller.rb` | Admin: review unlinked contacts, create & link users |

## Credentials

Stored in Rails encrypted credentials (`bin/rails credentials:edit`):

```yaml
line:
  channel_secret: "..."
  channel_access_token: "..."
```

## Account Linking

### Standard flow (user-initiated)

1. User logs into CP-API, visits `/line_account`, clicks "Generate Linking Code"
2. System saves a random token + 24-hour expiry on the user record
3. User sends `link <token>` to the LINE bot
4. LinkCommand looks up token, verifies expiry, sets `provider="line"` + `uid=<LINE userId>`, clears token
5. Bot replies "Linked successfully"

### Quick link (admin-initiated)

For VIPs who just chat without going through the linking flow. See `docs/line-quick-link.md` for full design.

1. Unlinked user messages the bot → recorded as `LineContact` (bounded, rate-limited)
2. Admin visits `/line_contacts`, sees the contact with recent messages
3. Admin clicks "Create & Link" → fills in user details → user created with LINE already linked
4. VIP does nothing — next message goes through the LLM

## Adding Commands

1. Create `app/services/line/commands/your_command.rb` extending `BaseCommand`
2. Add entry to `COMMAND_MAP` in `app/services/line/message_router.rb`

## Adding Tools

1. Create `app/services/line/tools/your_tool.rb` with `DEFINITION` hash and `.call(arguments)` method
2. Register in `config/initializers/line_tools.rb`
3. See `docs/llm-data-query.md` for the planned meta-tool pattern

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

## Dev Setup (LINE webhook via SSH tunnel)

1. Open SSH reverse tunnel to the proxy machine:
   ```
   ssh -R 3000:localhost:3000 10.44.0.2
   ```

   autossh version (with keepalives so it recovers from sleep/network drops):
   ```
   autossh -M 0 -o "ServerAliveInterval 15" -o "ServerAliveCountMax 3" -o "ExitOnForwardFailure yes" -R 3000:localhost:3000 10.44.0.2
   ```
   `-M 0` disables autossh's own monitoring port and relies on SSH keepalives instead.
   The remote (`10.44.0.2`) should also have `ClientAliveInterval 15` and `ClientAliveCountMax 3` in `/etc/ssh/sshd_config` so stale sessions are cleaned up quickly.
2. Zoraxy rule: `cp-line.nattee.net` → `http://localhost:3000`
3. LINE Console webhook URL: `https://cp-line.nattee.net/line/webhook`
4. `config/environments/development.rb` has `cp-line.nattee.net` in allowed hosts

## Production

Change Zoraxy target from `localhost:3000` to `10.0.5.59:3000` (or wherever the production server is) and drop the SSH tunnel.
