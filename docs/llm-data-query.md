# LLM Data Query via LINE Bot

Design doc for adding data query capabilities to the LINE bot's LLM chat.

## Problem

Users want to get department reports by chatting with the LLM in LINE (e.g. "What's my schedule?", "What does อ.สมชาย teach?"). The existing tool-calling infrastructure (ToolRegistry, ToolExecutor, LlmService multi-round loop) is in place but only has an EchoTool.

**Concern — code duplication**: The web app already has report pages (SchedulesController with 6 reports). Naively adding LLM tools would duplicate the query logic.

**Concern — model reliability**: Three Chinese open-source models (Qwen 2.5 32B, GLM-4.7, Kimi) are available. These are unreliable with many distinct tools — they confuse similar tools, mis-extract Thai parameters into JSON, and derail on multi-round chains. The more tools registered, the worse selection accuracy gets.

## Approach: Single Meta-Tool with Enum Dispatch

Instead of registering 10+ individual tools (which confuses smaller models), register **one tool** (`query_data`) with a `query_type` enum parameter:

```json
{
  "name": "query_data",
  "description": "Query department data: schedules, grades, course info, and staff schedules.",
  "parameters": {
    "type": "object",
    "properties": {
      "query_type": {
        "type": "string",
        "enum": ["my_schedule", "my_grades", "staff_schedule", "course_info"],
        "description": "Type of data to query"
      },
      "semester": {
        "type": "string",
        "description": "Semester in 'YEAR/NUMBER' format, e.g. '2568/1'. Omit for current semester."
      },
      "staff_name": {
        "type": "string",
        "description": "Staff member name (Thai or English) for staff_schedule query"
      },
      "course_no": {
        "type": "string",
        "description": "Course number (e.g. '2110327') for course_info query"
      }
    },
    "required": ["query_type"]
  }
}
```

The model only needs to:
1. Decide whether to call `query_data` (binary decision — easy)
2. Pick a `query_type` from a constrained enum (easy)
3. Fill relevant optional params

Internally, the tool dispatches to purpose-built query handler classes.

### Why not many tools?

| Concern | Many tools | One meta-tool |
|---|---|---|
| Tool selection accuracy | Degrades at 8-10 tools on 32B models | Binary call/no-call — trivial |
| Cross-model consistency | Must test every tool x every model | One tool definition, enum constrains choice |
| Thai parameter extraction | Each tool needs its own params | Shared param set, fewer things to get wrong |
| Adding new query types | New tool def + registration + testing | Add enum value + handler class |
| Context window usage | N tool definitions consume tokens | One definition, constant size |

### Why not shared query objects?

Web reports and LINE answers rarely want the same data shape. The web workload page renders a full pivot table; a LINE user asking "how much does Prof. Somchai teach?" wants one number. Shared query objects accumulate presentation-specific options and couple both callers. Instead, query handlers are small purpose-built classes — slight AR query duplication is acceptable.

### How responses work

The tool returns structured text (not raw data). The LLM receives this as a tool result and generates a natural language response. This means the bot is conversational ("Here's your schedule for this semester:") rather than dumping formatted text.

## Architecture

```
LINE message
  → MessageRouter (not a command)
  → ChatJob (async)
  → LlmService
    → vLLM API (with query_data tool definition)
    → model returns: tool_call { name: "query_data", arguments: { query_type: "staff_schedule", staff_name: "สมชาย" } }
    → ToolExecutor.execute(tool_calls, user: @user)
      → QueryTool.call(arguments, user:)
        → StaffScheduleHandler.call(arguments, user:)
          → DB query → formatted text
    → text result appended to conversation
    → vLLM API (second round — model generates natural language response from tool result)
    → final text reply → LINE
```

## Infrastructure Changes

### Add `student_id` to `users` table

No path exists from User → Student today. Needed for "my schedule" / "my grades" queries.

- Migration: add `student_id` bigint FK (nullable) referencing `students`
- Model: `belongs_to :student, optional: true` on User
- Admin links users to students via user form (add Student dropdown)

### Modify `ToolExecutor` to pass user context

Current: `handler.call(arguments)` — no user context.
New: `handler.call(arguments, user: user)` — so handlers can scope queries to the linked user and check authorization.

`LlmService` already has `@user` — just pass it through to `ToolExecutor.execute`.

### Update system prompt

Add one line to `config/llm.yml` system prompt mentioning the data query capability. Keep it short — the tool definition itself carries the parameter schema.

## Query Handlers

### `my_schedule` — "What's my schedule?"

- **Auth**: requires `user.student` (linked to a student record)
- **Params**: `semester` (optional, defaults to latest)
- **Query**: Grade → CourseOffering → Section → TimeSlots with Room
- **Output**:
  ```
  ตารางเรียน ภาคการศึกษา 2568/1

  2110327 Algorithm Design - Sec 1
    Mon 09:00-12:00 @ ENG3-318
    Wed 13:00-16:00 @ ENG3-318

  2110421 Database Systems - Sec 2
    Tue 09:00-12:00 @ ENG4-401

  Total: 2 courses
  ```
- **Reference**: `SchedulesController#student` (lines 146-189)

### `my_grades` — "What are my grades?"

- **Auth**: requires `user.student`
- **Params**: `semester` (optional, defaults to latest semester with grades)
- **Query**: `Grade.for_term(year, semester).where(student:).includes(:course)`
- **Output**:
  ```
  เกรด ภาคการศึกษา 2568/1

  2110327 Algorithm Design    - A
  2110421 Database Systems     - B+
  2110499 Project             - S

  GPA (term): 3.75
  Cumulative GPA: 3.42
  Total credits: 96
  ```

### `staff_schedule` — "What does อ.สมชาย teach?"

- **Auth**: any linked user (public info)
- **Params**: `staff_name` (required), `semester` (optional)
- **Staff lookup**: fuzzy match on `first_name_th`, `last_name_th`, `first_name`, `last_name` using `LIKE`. If multiple matches, return disambiguation list. If none, return error.
- **Query**: Teaching → section_ids → TimeSlots with Room + sum load_ratio
- **Output**:
  ```
  ตารางสอน ผศ.ดร.สมชาย สมิท ภาคการศึกษา 2568/1

  2110327 Algorithm Design - Sec 1
    Mon 09:00-12:00 @ ENG3-318
    Wed 13:00-16:00 @ ENG3-318

  2110421 Database Systems - Sec 1
    Tue 09:00-12:00 @ ENG4-401

  Total teaching load: 1.5
  ```
- **Reference**: `SchedulesController#staff` (lines 36-68)

### `course_info` — "What sections does 2110327 have?"

- **Auth**: any linked user
- **Params**: `course_no` (required), `semester` (optional)
- **Query**: Course → CourseOffering → Sections → TimeSlots + Teachings
- **Output**:
  ```
  2110327 Algorithm Design (3 credits) ภาคการศึกษา 2568/1

  Section 1
    Mon 09:00-12:00 @ ENG3-318
    Wed 13:00-16:00 @ ENG3-318
    Instructor: ผศ.ดร.สมชาย สมิท

  Section 2
    Tue 09:00-12:00 @ ENG4-401
    Thu 13:00-16:00 @ ENG4-401
    Instructor: รศ.ดร.สมหญิง จันทร์
  ```

## Future Handlers (Phase 3)

Expand `QUERY_TYPES` enum and `HANDLERS` hash in QueryTool. No infrastructure changes needed.

- `staff_workload` — teaching load summary (admin/editor only)
- `room_schedule` — room bookings (add `room_name` param to tool definition)

## Authorization Model

| Query type | Who can access | Check |
|---|---|---|
| `my_schedule` | User with linked student | `user.student.present?` |
| `my_grades` | User with linked student | `user.student.present?` |
| `staff_schedule` | Any linked user | `user.present?` |
| `course_info` | Any linked user | `user.present?` |
| `staff_workload` (future) | Admin/editor | `user.admin? \|\| user.editor?` |
| `room_schedule` (future) | Any linked user | `user.present?` |

All handlers receive the `user` object from `ToolExecutor`. Authorization failures return a human-readable error string that the LLM can relay to the user.

## Current Semester Resolution

`Semester.ordered.first` returns the latest semester by `year_be DESC, semester_number DESC`. If the user specifies a semester (e.g. "2568/1"), parse with `year, num = str.split("/")` and look up `Semester.find_by(year_be:, semester_number:)`.

## Files to Create/Modify

**Modify**:
- `app/services/line/tool_executor.rb` — add `user:` keyword param
- `app/services/line/llm_service.rb` — pass `user:` to ToolExecutor
- `app/services/line/tools/echo_tool.rb` — update `call` signature
- `config/initializers/line_tools.rb` — register `query_data`
- `config/llm.yml` — update system prompt
- `app/models/user.rb` — add `belongs_to :student, optional: true`
- `app/views/users/_form.html.haml` — add Student dropdown

**Create**:
- `db/migrate/XXXXXX_add_student_id_to_users.rb`
- `app/services/line/tools/query_tool.rb`
- `app/services/line/tools/query_handlers/base_handler.rb`
- `app/services/line/tools/query_handlers/my_schedule_handler.rb`
- `app/services/line/tools/query_handlers/my_grades_handler.rb`
- `app/services/line/tools/query_handlers/staff_schedule_handler.rb`
- `app/services/line/tools/query_handlers/course_info_handler.rb`

## Implementation Order

1. Infrastructure (migration, ToolExecutor user context, QueryTool meta-tool, BaseHandler)
2. `staff_schedule` handler first — needs no student linking, easiest to test
3. `course_info` handler — also no student linking
4. `my_schedule` + `my_grades` — requires admin to link a user to a student first
5. Tests after each handler
6. Manual E2E testing across all 3 models (Qwen, GLM, Kimi)
