# Backend LLM API — Calling Guide

How to call the department's self-hosted LLM backends directly. The servers run
**vLLM** and expose the standard **OpenAI-compatible Chat Completions API**, so
any OpenAI client library (or plain HTTP) works.

## Endpoints

| Backend | Base URL | `model` value to send |
|---|---|---|
| Qwen 2.5 Coder 32B (default) | `http://10.0.5.25:8000` | `/data/models/qwen2.5-coder-32b` |
| GLM-4.7 | `http://161.200.93.200:8000` | `glm-5` |
| Kimi | `http://161.200.93.200:8001` | `kimi` |

- Chat endpoint: `POST <base_url>/v1/chat/completions`
- List served models: `GET <base_url>/v1/models`
- Liveness check: `GET <base_url>/health`

## Access

- **No API key / no auth header.** Send `Content-Type: application/json` only.
- Servers are **intranet-only** — you must be on the university/department
  network (or VPN). They are not reachable from the public internet.

## Basic request

The request body is identical for all three backends — only the base URL and
the `model` value change.

**Qwen 2.5 Coder 32B:**

```bash
curl -s http://10.0.5.25:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/qwen2.5-coder-32b",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, who are you?"}
    ],
    "temperature": 0.7,
    "max_tokens": 4096,
    "repetition_penalty": 1.1
  }'
```

**GLM-4.7:**

```bash
curl -s http://161.200.93.200:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, who are you?"}
    ],
    "temperature": 0.7,
    "max_tokens": 4096,
    "repetition_penalty": 1.1
  }'
```

**Kimi:**

```bash
curl -s http://161.200.93.200:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kimi",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, who are you?"}
    ],
    "temperature": 0.7,
    "max_tokens": 4096,
    "repetition_penalty": 1.1
  }'
```

Notes on parameters:

- `model` is **required** and must match the table above exactly (for Qwen it
  is a filesystem path — that is correct, not a mistake).
- `max_tokens` — we use 4096; the server may reject larger values depending on
  context length.
- `repetition_penalty` is a vLLM extension (not in the OpenAI spec); 1.1 works
  well with these models. OpenAI client libraries pass it via
  `extra_body={"repetition_penalty": 1.1}`.
- Thai and English input both work; the models reply in the user's language.

The response is a standard OpenAI-format object — the reply text is at
`choices[0].message.content`, token usage in `usage`.

Two non-standard things to expect in responses:

- **GLM and Kimi** additionally return the model's chain-of-thought in
  `choices[0].message.reasoning_content`. Read `content` for the answer and
  ignore `reasoning_content`; note its tokens count toward `completion_tokens`.
- **Self-reported identity is unreliable** — these open-weight models may claim
  to be from OpenAI or Anthropic when asked who they are. This is a training
  artifact, not a deployment error. Pin the assistant's identity in your
  system prompt if it matters for your use case.

## Tool calling (function calling)

Pass tool definitions in the standard OpenAI `tools` format:

```bash
curl -s http://10.0.5.25:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/data/models/qwen2.5-coder-32b",
    "messages": [{"role": "user", "content": "What is the weather in Bangkok?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather for a city",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string", "description": "City name"}
          },
          "required": ["city"]
        }
      }
    }]
  }'
```

When the model decides to call a tool, the response contains
`choices[0].message.tool_calls` instead of text content. Execute the tool
yourself, then send a follow-up request appending (1) the assistant message
with the `tool_calls`, and (2) one `{"role": "tool", "tool_call_id": ...,
"content": "<result>"}` message per call, to get the final text answer.

### Known model quirks

These are open-weight models and tool calling is less reliable than commercial
APIs. Observed in production:

- **Qwen** sometimes refuses tool calls citing privacy, or emits the call as
  `<tool_call>{...}</tool_call>` text inside `content` instead of the
  structured `tool_calls` array. Be prepared to parse content as a fallback.
- **GLM** uses inconsistent tool-call output formats (sometimes
  ` ```action ` code blocks, sometimes `<arg_key>/<arg_value>` XML).
- Keep the number of tools small (well under 8–10) — selection accuracy
  degrades quickly on these model sizes.

## Using OpenAI client libraries

Any OpenAI SDK works by overriding the base URL:

```python
from openai import OpenAI

client = OpenAI(base_url="http://10.0.5.25:8000/v1", api_key="none")  # key is ignored but required by the SDK
resp = client.chat.completions.create(
    model="/data/models/qwen2.5-coder-32b",
    messages=[{"role": "user", "content": "Hello"}],
    max_tokens=4096,
    extra_body={"repetition_penalty": 1.1},
)
print(resp.choices[0].message.content)
```

## Errors & limits

- Non-2xx responses return a JSON error body from vLLM — the message usually
  pinpoints the problem (e.g. invalid JSON, context length exceeded).
- Typical timeouts to use as a client: connect ~10 s, read ~60 s (long
  generations can take tens of seconds).
- There is no rate limiting, but these are shared single-GPU servers — please
  avoid sustained parallel load.
