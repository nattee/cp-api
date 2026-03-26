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
LINE chatbot uses vLLM (Qwen 2.5 32B) with tool calling to handle:
- Information retrieval (direct LLM response)
- Google Calendar event creation
- GitHub issue creation

## Architecture
- WebhookController receives LINE webhook, enqueues ChatJob
- ChatJob calls LlmService which runs the tool-calling loop
- LlmService sends messages + tool definitions to vLLM
- When vLLM returns tool_calls, ToolExecutor dispatches to handler classes
- Results are sent back to vLLM for the next round
- Loop ends when vLLM returns plain text (max 5 rounds)
- Reply via reply_token, fallback to push_message if expired

## Key classes
- LlmService — manages conversation loop with vLLM
- ToolRegistry — maps tool names to definitions + handlers
- ToolExecutor — dispatches tool calls, wraps errors
- CalendarTool — Google Calendar API wrapper
- GithubIssueTool — Octokit wrapper
- ChatJob — ActiveJob that ties it all together

## vLLM endpoint
- Add a .yml config file
    - Base URL: http://localhost:8000
    - Endpoint: POST /v1/chat/completions
- OpenAI-compatible format with tools parameter

## LINE integration
- Reply token expires ~30s, fallback to push API
- Pass both reply_token and user_id to ChatJob

