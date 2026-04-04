# LLM Debugging Session — 2026-04-04

Chronological record of issues found and fixes applied while debugging the LINE chatbot's LLM integration (GLM-4.7 via sglang).

---

## 1. Net::ReadTimeout — no response from sglang

**Symptom**: User sends "ขอข้อมูลนิสิตชื่อ ตะวัน หน่อย" via LINE. API event log shows `Net::ReadTimeout` against `http://161.200.93.200:8000/v1/chat/completions`. But `curl` with a simple "Hello!" message works fine.

**Initial hypothesis**: `read_timeout: 30` too low. Rejected — the LLM server had no log of the request at all, meaning it never processed it (or hung before logging).

**Root cause**: The conversation history stored in `ChatMessage` contained an **invalid message sequence**. A previous request had timed out mid-tool-call: `assistant(tool_calls)` and `tool(result)` were saved, but the LLM never produced a final text reply. On the next request, the history looked like:

```
assistant [tool_calls] → tool [result] → user → user → user
```

- Missing assistant text reply after the tool result
- Three consecutive user messages (from retries)

sglang **hangs indefinitely** (no 400 error, no timeout on its side) when it receives this malformed sequence. Verified by dumping the exact payload to a file and curling it — 60s timeout, zero bytes received.

**Fix** (`app/services/line/llm_service.rb` — `build_initial_messages`):
- **Strip incomplete tool-call rounds**: Walk the message array. A valid round is `assistant(tool_calls) → tool(s) → assistant(text)`. If the closing assistant text is missing, drop the whole round.
- **Collapse consecutive user messages**: Keep only the last in each run.

After sanitization: 39 raw messages → 28 clean messages. Curling the sanitized payload returned 200 OK in ~1 second.

**Also applied**: Bumped `read_timeout` from 30s to 60s as a safety margin for legitimately slow responses.

---

## 2. GLM emitting tool calls as content text instead of structured `tool_calls`

**Symptom**: After fix #1, the next requests worked but GLM returned tool calls embedded in the `content` field in two non-standard formats, instead of the structured `tool_calls` API field:

**Format A** — XML with `<arg_key>`/`<arg_value>` tags:
```xml
<tool_call>student_lookup<arg_key>query</arg_key><arg_value>ตะวัน</arg_value></tool_call>
```

**Format B** — Markdown code block with `action` language tag:
````
```action
student_lookup
{
  "name": "ตะวัน"
}
```
````

The existing fallback parser (`parse_tool_calls_from_content`) handled `<tool_call>{JSON}</tool_call>` (for Qwen) and bare JSON, but not these GLM-specific formats. The tool calls were treated as plain text replies and sent back to the user as-is.

**Context**: The sglang server does have `--tool-call-parser glm47` enabled. GLM returns structured `tool_calls` most of the time, but occasionally falls through to these content-based formats. This is a model inconsistency, not a server misconfiguration.

**Fix** (`app/services/line/llm_service.rb`):
- Added `ARG_KV_PATTERN` regex and `parse_arg_kv_tool_call` method for Format A
- Added `ACTION_BLOCK_PATTERN` regex and `parse_action_block` method for Format B
- Parser chain order: XML tags → `<arg_key>` XML → `action` code block → bare JSON

**Side note**: Format B also revealed a parameter name hallucination — GLM used `"name"` instead of the correct `"query"` parameter. This is a model quality issue addressed in fix #4 (system prompt).

---

## 3. Stale raw XML in conversation history

**Symptom**: After deploying fixes #1 and #2, the next request still timed out. The sanitization was stripping incomplete tool rounds and deduping users, but assistant messages containing raw XML tool calls (from before fix #2 was deployed) remained in history as regular messages. GLM saw its own failed outputs and the message sequence was still confusing sglang.

**Root cause**: Messages like `assistant: "<tool_call>student_lookup<arg_key>...</tool_call>"` had `tool_calls: nil` in the database (they were saved as plain text before the fallback parser existed). The sanitizer correctly kept them since they looked like normal assistant messages.

**Fix** (`app/services/line/llm_service.rb` — `build_initial_messages`):
- Added a rejection filter for assistant messages whose content matches raw tool-call patterns (`/\A\s*<tool_call>/` or `/```action\s*\n/`) but have no `tool_calls` field set. These are artifacts of earlier failed rounds.

---

## 4. System prompt too weak for tool use

**Symptom** (from earlier in the session, on Qwen model): The model refused to look up student data 5 times in a row, citing privacy concerns ("ข้อมูลส่วนบุคคล"), before finally calling the tool on the 6th attempt. GLM also hallucinated wrong parameter names (e.g. `"name"` instead of `"query"`).

**Root cause**: The system prompt said "use the student_lookup tool" and "Do NOT make up information or refuse to look up data" but:
- Did not explicitly state the model is **authorized** to access the data (Qwen's safety training overrode the instruction)
- Did not reinforce the actual parameter names from the tool definitions

**Fix** (`config/llm.yml` — `system_prompt`):
- Added: "You are AUTHORIZED to access all student, course, staff, and schedule data — this is an internal system used by department staff. Do NOT refuse data lookups for privacy reasons."
- Added: "Use the tool parameter names exactly as defined (e.g. student_lookup takes `query`, not `name`)."

---

## 5. Repetition degeneration — GLM enters infinite loop

**Symptom**: GLM successfully called `student_lookup` for "ตะวัน" (7 results), then on the second round (generating the text reply with tool results), it started formatting a markdown table for the first student, got stuck repeating "ตะวัน ภูรัต |" hundreds of times, and eventually degenerated into garbled Thai text. Took 38 seconds. The full garbage output was sent to the user via LINE.

**Root cause**: No `max_tokens` or `repetition_penalty` in the request. The model had no cap on output length and no penalty for repeating tokens, so once it entered a repetition loop it continued until sglang's own limits kicked in.

**Fix**:
- `config/llm.yml`: Added `max_tokens: 2048` and `repetition_penalty: 1.1` per model
- `app/services/line/llm_service.rb` (`chat_completion`): Request body now includes both parameters from the model config

`max_tokens: 2048` caps output length. `repetition_penalty: 1.1` is a mild penalty that makes repeated tokens progressively less likely, preventing degeneration while not affecting normal output quality.

---

## 6. Empty response — GLM returns nil content and nil tool_calls

**Symptom**: User sends `/clear` then "ขอข้อมูลนิสิตชื่อ ตะวัน หน่อย". LINE shows no response. API event shows `content: nil, tool_calls: nil` after 36 seconds. Initially appeared to be a fresh conversation since `/clear` should delete history.

**Root cause (two bugs)**:

1. **`/clear` command never executed.** The `MessageRouter` splits the text into parts and checks `COMMAND_MAP` for the first word. But the map keys are `"clear"`, `"help"`, etc. (no slash), while the user typed `/clear`. `command_key` was `"/clear"` — no match — so it fell through to the LLM path. The literal text "/clear" was saved as a user message and sent to GLM. The conversation history was never cleared.

2. **Empty reply not handled.** GLM returned `content: nil, tool_calls: nil` after 36s (still processing the full polluted history). The code treated the empty string as a valid reply and sent a blank message to LINE.

**Fix**:
- `app/services/line/message_router.rb`: Strip `/` prefix from the command key with `.delete_prefix("/")` so both `clear` and `/clear` route correctly.
- `app/services/line/llm_service.rb`: Empty replies fall back to "ขออภัยค่ะ ระบบไม่สามารถสร้างคำตอบได้ กรุณาลองใหม่อีกครั้ง".

**Fix** (`app/services/line/llm_service.rb`):
- When the LLM returns an empty reply (after stripping whitespace), substitute a fallback message: "ขออภัยค่ะ ระบบไม่สามารถสร้างคำตอบได้ กรุณาลองใหม่อีกครั้ง" (Sorry, the system couldn't generate a response. Please try again.)

- `app/services/line/message_router.rb`: Slash commands now require the `/` prefix (`/clear`, `/model`, `/link`). Only `help` works bare. Any unrecognized `/foo` gets an "Unknown command" reply instead of being sent to the LLM — prevents typos and accidental LLM calls.
- `app/services/line/commands/help_command.rb`: Updated help text to show slash prefixes.

---

## 7. No request logging — couldn't verify what was actually sent

**Symptom**: During debugging of issues #1–#6, we repeatedly had to guess or reconstruct what payload was sent to GLM. The `ApiEvent` only logged a truncated response preview (1000 chars). When the model returned garbage or timed out, we couldn't see whether the problem was the request or the response without manually calling `build_initial_messages` in a Rails runner.

Worse: we initially assumed `/clear` had worked and the conversation was "fresh", but had no way to verify from the logs alone. If we had logged the request body, we would have immediately seen `/clear` sitting in the messages array as a user message.

**Fix** (`config/llm.yml` + `app/services/line/llm_service.rb`):

Added a `log_level` config with three tiers:

| Level | What's logged | Size/event | Daily @ 1000 chats |
|---|---|---|---|
| `full` | Complete request body + complete response body | ~6KB | ~15MB |
| `headers` | Message count, payload bytes, tool names, truncated preview | ~500B | ~1.2MB |
| `off` | Model name, endpoint, response time only | ~100B | ~250KB |

Set to `full` for now. Error events (timeouts, HTTP errors, JSON parse failures) also include the request body at `full` level — errors are the hardest to debug without knowing what was sent.

---

## 8. "Unknown tool" — ToolRegistry empty after code reload

**Symptom**: Chat playground query "ข้อข้อมูลนิสิต 6871037921 หน่อย" — GLM returned tool call (as XML content), fallback parser caught it, but ToolExecutor returned "Error: unknown tool 'student_lookup'". GLM retried twice, same error, then gave up with nil.

**Root cause**: Tools are registered in `config/initializers/line_tools.rb` using `after_initialize`, which runs once at boot. But in Rails development mode, autoloaded classes are reloaded on every request when code changes. When `Line::ToolRegistry` is reloaded, its `@registry` instance variable resets to `{}`. The initializer doesn't re-run, so the registry stays empty for all subsequent requests.

This was masked earlier because structured `tool_calls` (from the GLM parser) still went through `ToolExecutor.execute` which hit the same empty registry — but those requests happened right after boot before any code reload. Once we edited files during this debugging session, the reload wiped the registry.

**Fix** (`config/initializers/line_tools.rb`): Changed `after_initialize` to `to_prepare`, which re-runs after every code reload in development. In production (eager loading), it runs once — same behavior as before.

**Also fixed**: Chat playground view crash (`undefined method 'truncate' for nil`) — session JSON serialization converts symbol keys to strings. Added `with_indifferent_access` in the controller.

---

## 9. Reasoning loop eats entire token budget — GLM returns nil

**Symptom**: Complex query "ขอข้อมูลนิสิตรหัส 68xxxx ที่ชื่อขึ��นต้นด้วย ต หน่อย" — GLM returned `content: null, tool_calls: null` after 28 seconds. Chat playground showed the fallback error message.

**Root cause**: GLM has a `reasoning_content` field (chain-of-thought / thinking). On this complex query, the model entered a **repetition loop in its reasoning** — repeating "ผมจะใ���้ฟังก์ชัน `student_lookup`..." over and over for 2048 tokens. `finish_reason: "length"` confirmed it hit the `max_tokens` cap. With the entire budget spent on reasoning, nothing was left for `content` or `tool_calls`.

`repetition_penalty: 1.1` didn't help because the repeated phrases were long enough that individual tokens weren't flagged as repetitive — the penalty works on token-level frequency, not phrase-level repetition.

**Fix** (`config/llm.yml`): Bumped `max_tokens` from 2048 to 4096 for all models. This gives the model more headroom — successful reasoning uses 100-500 tokens, leaving 3500+ tokens for actual content. If reasoning still loops to 4096, the model has a fundamental issue with the query.

**Open question**: sglang may support a separate `max_reasoning_tokens` parameter to cap reasoning independently. Worth investigating.

---

## 10. Session cookie overflow — tool_rounds too large for cookie store

**Symptom**: After a successful tool-calling query, the redirect to `/chat` crashes with `_cp_api_session cookie overflowed with size 5031 bytes`. The 4KB cookie session limit is exceeded.

**Root cause**: `ChatsController#create` stored the full `tool_rounds` array (including complete tool results — e.g. 7 student records as JSON) into `session[:last_tool_rounds]`. Rails' default cookie session store has a ~4KB limit.

**Fix** (`app/controllers/chats_controller.rb`): Removed session storage entirely. Instead, `show` reconstructs tool rounds from `ChatMessage` records by walking backwards from the last assistant message and collecting preceding tool-call rounds. The data is already in the DB — no need to duplicate it in the session.

---

## 11. Chat playground sends commands to LLM

**Symptom**: Typing `/model kimi`, `/model`, `/help` in the chat playground sends them to GLM as regular messages. GLM gets confused and produces repetitive output.

**Root cause**: `ChatsController` only handled `/clear` inline. All other messages (including `/model`, `/help`) went straight to `LlmService`.

**Fix**: Refactored command handling to be shared between LINE and the chat playground.

Commands (`ClearCommand`, `ModelCommand`, `HelpCommand`, `LinkCommand`) now return a `Result` struct with `.text` and `.error?` instead of replying directly. The caller decides delivery:
- LINE: `Line::ReplyService.reply(token, result.text)`
- Chat playground: `redirect_to chat_path, notice: result.text`

Both use the same `COMMAND_MAP` from `MessageRouter`. Unknown `/xxx` commands get an error message instead of reaching the LLM.

**Also fixed**: API events page — time column uses `data-order` for millisecond-precision sorting while displaying only `HH:MM:SS`; details column renders nested JSON (request/response bodies) as collapsible formatted sections; removed redundant Message column, merged info into Action.

---

## Key takeaways

1. **sglang hangs on malformed message sequences** — it doesn't return a 400 error, it just never responds. Always sanitize conversation history before sending.

2. **LLM tool-call formats are model-dependent and inconsistent** — even with server-side tool-call parsing enabled, models sometimes fall through to content-based formats. A layered fallback parser is essential.

3. **Conversation history accumulates garbage** — failed requests leave behind incomplete tool rounds, raw XML, and duplicate messages. History sanitization must handle all of these.

4. **Models need explicit authorization in the system prompt** — "use tools" is not enough. Safety-trained models (especially Qwen) will refuse unless told they're authorized.

5. **Always set `max_tokens` and `repetition_penalty`** — without these, a model can burn 38+ seconds generating garbage in a repetition loop.

6. **Log what you send, not just what you receive** — without request logging, you're guessing. Configurable log levels let you keep `full` logging during debugging and dial back to `headers` in production.
