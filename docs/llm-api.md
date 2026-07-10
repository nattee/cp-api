# Backend LLM API — Calling Guide

How to call the department's self-hosted LLM backends directly. All endpoints
expose the standard **OpenAI-compatible Chat Completions API**, so any OpenAI
client library (or plain HTTP) works. The DGX runs **SGLang**; the A100 box
runs **vLLM** — the API is the same either way.

Canonical provider-side contract: `~/dgx-b200/docs/llm-service-contract.md`
(this doc is the cp-api-side summary).

## Endpoints

| Backend | Base URL | `model` to send | Availability |
|---|---|---|---|
| Qwen3.5 397B (default) | `http://161.200.93.200:8000` | `qwen3.5` | **default resident** — up unless an alternate was swapped in; auto-returns after reboot |
| GLM-5.2 | `http://161.200.93.200:8001` | `glm-5.2` | swap resident — **usually OFF** |
| Kimi K2.6 | `http://161.200.93.200:8002` | `kimi-k2.6` | swap resident — **usually OFF** |
| Gemma 4 31B | `http://10.0.5.25:8000` | `gemma-4-31b` | always-on side model |

- Chat endpoint: `POST <base_url>/v1/chat/completions`
- List served models: `GET <base_url>/v1/models`
- Liveness check: `GET <base_url>/health`

### The swap slot (read this once)

DGX ports 8000–8002 share the same 4 GPUs: **exactly one is alive at any
moment**. The other two refuse TCP connections — that is *normal operation*,
not an outage. Probe `/health` to discover the live resident. Build against
`:8000` (Qwen); treat `:8001`/`:8002` as occasionally-available experiments,
never as fallbacks.

## Access

- **No API key / no auth header.** Send `Content-Type: application/json` only.
- Servers are **intranet-only** — university/department network (or VPN).

## Basic request

Identical body for all backends — only base URL and `model` change:

```bash
curl -s http://161.200.93.200:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, who are you?"}
    ],
    "temperature": 0.7,
    "max_tokens": 4096
  }'
```

Notes on parameters:

- `model` — see the table. On the DGX the value is echoed, not validated (a
  wrong name still answers — the *port* selects the model). On `10.0.5.25`
  vLLM **validates**: wrong names get an error.
- `max_tokens` — use **at least 512, we standardize on 4096**. The DGX models
  are reasoning models: they think before answering, and the thinking counts
  against `max_tokens`. Small budgets can be consumed entirely by reasoning,
  yielding an **empty `content`** — that is the classic symptom.
- `repetition_penalty` is no longer recommended (it was tuned for the retired
  qwen2.5-coder; on reasoning models it degrades the thinking trace). The
  server defaults are correct.
- Thai and English both work; Qwen3.5 has the strongest Thai of the set.

The response is a standard OpenAI-format object — reply text at
`choices[0].message.content`, usage in `usage`.

Non-standard things to expect:

- All three DGX models return chain-of-thought in
  `choices[0].message.reasoning_content`. Read `content`; ignore
  `reasoning_content` (its tokens count toward `completion_tokens`).
- **Self-reported identity is unreliable** — open-weight models may claim to
  be from OpenAI or Anthropic. Training artifact, not a deployment error.
  Pin identity in your system prompt if it matters.

## Vision (image input) — NEW

`qwen3.5`, `kimi-k2.6`, and `gemma-4-31b` accept images (`glm-5.2` is
text-only). Send a content array with `image_url` parts (data: URIs or
intranet-reachable URLs):

```bash
curl -s http://161.200.93.200:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5",
    "max_tokens": 4096,
    "messages": [{"role": "user", "content": [
      {"type": "text", "text": "อ่านตารางเรียนในรูปนี้ให้หน่อย"},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<...>"}}
    ]}]
  }'
```

(Relevant for the LINE bot: user-sent photos can now be forwarded to the
model instead of being ignored.)

## Tool calling (function calling)

Standard OpenAI `tools` format, tested end-to-end on all DGX residents
(best-effort on Gemma):

```bash
curl -s http://161.200.93.200:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5",
    "max_tokens": 4096,
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

Tool-call responses populate `choices[0].message.tool_calls`; execute the
tool, then send a follow-up appending the assistant message and one
`{"role": "tool", "tool_call_id": ..., "content": "<result>"}` per call.

### Known model quirks

- The old generation's habit of emitting tool calls as text inside `content`
  is largely fixed by server-side parsers, but keep the content-parsing
  fallback in `LlmService` — cheap insurance.
- Keep the number of tools small (well under 8–10); selection accuracy still
  degrades with large tool sets.

## Using OpenAI client libraries

```python
from openai import OpenAI

client = OpenAI(base_url="http://161.200.93.200:8000/v1", api_key="none")
resp = client.chat.completions.create(
    model="qwen3.5",
    messages=[{"role": "user", "content": "Hello"}],
    max_tokens=4096,
)
print(resp.choices[0].message.content)
```

## Errors & limits

- Non-2xx responses return a JSON error body naming the problem (invalid
  JSON, context length exceeded, unknown model on the vLLM box).
- Connection refused on a DGX port = that resident isn't live (see swap
  slot); connection refused on ALL DGX ports = actual outage.
- Client timeouts: connect ~10 s, read ~120 s (reasoning models take longer
  than the old generation before first output).
- No rate limiting; sized for ≤30 concurrent sessions. Sustained heavy
  parallel load will queue, not error.

## History

- 2026-07: upgraded from GLM-5/Kimi-K2.5/qwen2.5-coder-32b to the lineup
  above. The old endpoints and model names are **gone** (qwen2.5 on
  10.0.5.25 was retired when Gemma took that box).
