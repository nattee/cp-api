	# ChulaBooster External API — Client Guide

A read-only API for trusted external apps (department portals, LMS, ETL jobs) to
fetch ChulaBooster data under per-app permissions and per-app data scoping.

You will be handed two credentials by a ChulaBooster admin:

- **`app_id`** — your application identifier (e.g. `svc-deptportal`)
- **`app_secret`** — a secret string, shown **once** at creation. Store it
  securely; it cannot be retrieved again (only reset).

## Authentication

Send both on every request as HTTP headers:

| Header | Value |
|--------|-------|
| `DeeAppId` | your `app_id` |
| `DeeAppSecret` | your `app_secret` |

All endpoints live under `https://<booster-host>/api/ext/`.

## Quick test (curl)

```bash
BASE=https://booster.cloud.cp.eng.chula.ac.th           # the ChulaBooster URL you were given
APP_ID=svc-deptportal
APP_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxx   # the secret shown once at creation

# interactive search (capability: read:students)
curl -s "$BASE/api/ext/students?query=สมชาย&limit=20" \
  -H "DeeAppId: $APP_ID" -H "DeeAppSecret: $APP_SECRET"

# class roster (capability: read:roster)
curl -s "$BASE/api/ext/roster/CS101-1" \
  -H "DeeAppId: $APP_ID" -H "DeeAppSecret: $APP_SECRET"
```

## Python — simple read

```python
import requests

BASE = "https://your-booster-host"
HEADERS = {"DeeAppId": "svc-deptportal", "DeeAppSecret": "xxxx…"}

def ext_get(path, **params):
    r = requests.get(f"{BASE}/api/ext/{path}", headers=HEADERS,
                     params=params, timeout=30)
    r.raise_for_status()       # 401 unauth, 403 missing capability, 400 bad args
    return r.json()

print(ext_get("students", query="สมชาย", limit=20))
print(ext_get("courses",  query="2110101"))
print(ext_get("roster/CS101-1"))
```

## Python — bulk ETL export (keyset pagination + nightly delta)

The `export:*` family is built for mirroring whole tables: keyset pagination plus
incremental deltas. Page until `next_cursor` is `null`; on the next run pass
`changed_since` (ISO 8601) to fetch only rows changed since then.

```python
import requests

BASE = "https://your-booster-host"
HEADERS = {"DeeAppId": "svc-etl-2110", "DeeAppSecret": "xxxx…"}

def export_all(entity, changed_since=None):
    """Yield every row of /api/ext/export/<entity>, following the cursor."""
    cursor = None
    while True:
        params = {"limit": 500}
        if cursor:        params["cursor"] = cursor
        if changed_since: params["changed_since"] = changed_since
        r = requests.get(f"{BASE}/api/ext/export/{entity}",
                         headers=HEADERS, params=params, timeout=60)
        r.raise_for_status()
        data = r.json()
        yield from data[entity]              # e.g. data["students"]
        cursor = data.get("next_cursor")
        if not cursor:                       # last page → done
            break

# full extract
for row in export_all("students"):
    ...  # upsert into your warehouse

# incremental: only rows changed since the previous run started
for row in export_all("students", changed_since="2026-06-29T02:00:00"):
    ...
```

The export response shape is `{"count": N, "<entity>": [...], "next_cursor": "…"|null}`.
Rows are ordered by `(update_time, primary_key)`. The last page is the one
shorter than `limit` (its `next_cursor` is `null`). Hard deletes are not
observable here — do a periodic full re-pull if you must reconcile deletions.

## Endpoints & required capabilities

| Endpoint | Capability | Notes |
|----------|-----------|-------|
| `GET /api/ext/roster/{class_section_id}` | `read:roster` | one class section's roster |
| `GET /api/ext/students?query=&limit=` | `read:students` | search; capped at 200 rows |
| `GET /api/ext/courses?query=&limit=` | `read:courses` | search |
| `GET /api/ext/schedules?query=&limit=` | `read:schedules` | search |
| `GET /api/ext/export/students` | `export:students` | bulk; `cursor`/`changed_since`/`limit≤500` |
| `GET /api/ext/export/courses` | `export:courses` | bulk |
| `GET /api/ext/export/student_courses` | `export:student_courses` | bulk (enrolments + grades) |
| `GET /api/ext/export/programs` | `export:programs` | bulk |
| `GET /api/ext/export/program_courses` | `export:program_courses` | bulk |

Your key is granted a specific subset of these capabilities. Calling an endpoint
whose capability you don't hold returns `403 permission_denied`.

## What you can and can't see

- **Capabilities** decide *which endpoints* you may call.
- Your key's **bound service user** decides *which rows* you see, via the same
  role-based access control a human goes through. A department-scoped key returns
  only that department's rows; the `read:students` and all `export:*` endpoints
  require a bound user and return **no rows** without one (fail closed).
- **PII is redacted**: `national_id` comes back masked.
- This API is **read-only**. There are no write endpoints.

## Lifecycle

- Every authenticated request extends your key's validity to **90 days** from
  that moment (sliding window). A key unused for 90 days expires.
- An admin can disable a key at any time. A disabled or expired key is rejected
  on every request.

## Errors

| Status | Meaning |
|--------|---------|
| `401` | missing or invalid `DeeAppId` / `DeeAppSecret`, or key disabled/expired |
| `403` | `permission_denied` — your key lacks the capability, or no bound user |
| `400` | bad arguments (e.g. malformed `cursor` or `changed_since`) |

Responses are always JSON. On error the body is `{"error": "<code>", "detail": "…"}`.
