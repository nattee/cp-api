# LINE LLM Tool Expansion Round 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an LLM tool-selection eval harness (with breaking-point sweep), thread the calling user through the tool pipeline, and add four new LINE chatbot tools plus a staff_lookup extension — gated on measured tool-selection accuracy.

**Architecture:** Selection-only eval harness (`LlmEval::Runner/Scorer/RegistryBuilder` + YAML cases/decoys + rake task) measures tool-call accuracy against live vLLM endpoints without executing tools. New tools follow the existing `Line::Tools::*` one-class-per-tool pattern with `DEFINITION` constants; shared computation goes in `GradeStats::*` services. Spec: `docs/superpowers/specs/2026-07-21-line-tool-expansion-round2-design.md`.

**Tech Stack:** Ruby 3.4.8 / Rails 8.1, Minitest + fixtures, Net::HTTP against vLLM OpenAI-compatible API, Mercurial.

## Global Constraints

- **Version control is Mercurial (hg), not git.** No `.git` directory exists. Commit with `hg commit <explicit files> -m "..."` — always name the files explicitly (the repo may have unrelated dirty changes). Add new files with `hg add <file>` first.
- **Commit messages lead with WHY, not what.** First paragraph = problem/motivation; second part = what changed.
- **Tool handler signature (after Task 2):** `def self.call(arguments, user: nil)` — `arguments` is a Hash with **string** keys; return value is always a JSON **string**; errors are `{ error: "human-readable message" }.to_json`.
- **Era rules:** `Grade#year_ce` stores C.E. (2024). `students.admission_year_be`, `semesters.year_be` store B.E. (2567). Term labels shown to the LLM are B.E. `"2567/1"` (= `year_ce + 543`). Year params accept both eras: values `< 2400` are treated as C.E. GPA = semester average, GPAX = cumulative (Chula transcript convention — never invent other terms).
- **Run unit tests with `bin/rails test <file>`**. Never use `bin/rails test:system <file>` (it ignores the file argument). Full suite: `bin/rails test`.
- **No new gems.** Net::HTTP, YAML, CSV from stdlib.
- Tool `description` strings are the LLM-facing API: English, state *when to use the tool*, and disambiguate from sibling tools.
- Test env loads `config/llm.yml` (test section mirrors default) — `LLM_CONFIG` is available everywhere.

---

### Task 1: Extract `Line::ToolCallParser` from LlmService

The eval harness must parse content-embedded tool calls (GLM emits `<tool_call>` tags / ```action blocks instead of structured `tool_calls`) **exactly** the way production does. The parser currently lives as private methods inside `LlmService`. Extract it verbatim into a module both can use.

**Files:**
- Create: `app/services/line/tool_call_parser.rb`
- Modify: `app/services/line/llm_service.rb` (delete private parser methods + constants, call the module)
- Test: `test/services/line/tool_call_parser_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Line::ToolCallParser.parse(content) → Array<Hash> | nil` — OpenAI-format tool_call hashes (`{"id" => ..., "type" => "function", "function" => {"name" => ..., "arguments" => <JSON string>}}`), or nil when content has none. Used by Task 6's Runner.

- [ ] **Step 1: Write the failing test**

Create `test/services/line/tool_call_parser_test.rb`:

```ruby
require "test_helper"

class Line::ToolCallParserTest < ActiveSupport::TestCase
  test "parses XML-wrapped JSON tool call" do
    content = '<tool_call>{"name": "student_lookup", "arguments": {"query": "6732100021"}}</tool_call>'
    calls = Line::ToolCallParser.parse(content)

    assert_equal 1, calls.size
    assert_equal "student_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "6732100021" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses GLM arg_key/arg_value format" do
    content = "<tool_call>course_lookup<arg_key>query</arg_key><arg_value>2110327</arg_value></tool_call>"
    calls = Line::ToolCallParser.parse(content)

    assert_equal "course_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "2110327" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses action code block format" do
    content = "```action\nstaff_lookup\n{\"query\": \"สมิธ\"}\n```"
    calls = Line::ToolCallParser.parse(content)

    assert_equal "staff_lookup", calls.first.dig("function", "name")
    assert_equal({ "query" => "สมิธ" }, JSON.parse(calls.first.dig("function", "arguments")))
  end

  test "parses bare JSON line" do
    content = '{"name": "search", "arguments": {"query": "NNN"}}'
    calls = Line::ToolCallParser.parse(content)

    assert_equal "search", calls.first.dig("function", "name")
  end

  test "returns nil for plain text" do
    assert_nil Line::ToolCallParser.parse("สวัสดีค่ะ มีอะไรให้ช่วยไหมคะ")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/line/tool_call_parser_test.rb`
Expected: FAIL — `NameError: uninitialized constant Line::ToolCallParser`

- [ ] **Step 3: Create the module**

Create `app/services/line/tool_call_parser.rb`. The method bodies are **moved verbatim** from `app/services/line/llm_service.rb` (constants `TOOL_CALL_PATTERN`, `ACTION_BLOCK_PATTERN`, `ARG_KV_PATTERN` and methods `parse_tool_calls_from_content` → renamed `parse`, `build_calls_from_matches`, `parse_arg_kv_tool_call`, `parse_action_block`, `try_parse_bare_tool_call`, `parse_single_tool_json`):

```ruby
# Parses tool calls that models embed in message CONTENT instead of the
# structured tool_calls array: <tool_call>/<tools> XML tags (JSON or GLM's
# <arg_key>/<arg_value> pairs inside), ```action``` code blocks, and bare
# JSON lines with "name" + "arguments" keys. Returns an array of tool_call
# hashes in OpenAI format, or nil when the content contains none.
#
# Extracted from LlmService so the llm:eval harness (lib/tasks/llm_eval.rake)
# scores content-embedded tool calls exactly the way production does.
module Line::ToolCallParser
  TOOL_CALL_PATTERN = /<tool_call>\s*(.*?)\s*<\/tool_call>|<tools>\s*(.*?)\s*<\/tools>/m
  ACTION_BLOCK_PATTERN = /```action\s*\n(\S+)\s*\n(.*?)```/m
  ARG_KV_PATTERN = /<arg_key>\s*(.*?)\s*<\/arg_key>\s*<arg_value>\s*(.*?)\s*<\/arg_value>/m

  module_function

  def parse(content)
    matches = content.scan(TOOL_CALL_PATTERN)
    return build_calls_from_matches(matches) if matches.present?

    action = parse_action_block(content)
    return action if action.present?

    try_parse_bare_tool_call(content).presence
  end

  def build_calls_from_matches(matches)
    calls = matches.flat_map do |tool_call_match, tools_match|
      raw = (tool_call_match || tools_match).strip

      if raw.match?(ARG_KV_PATTERN)
        parse_arg_kv_tool_call(raw)
      else
        raw.split("\n").filter_map { |line| parse_single_tool_json(line) }
      end
    end
    calls.presence
  end

  def parse_arg_kv_tool_call(raw)
    name = raw.sub(/<arg_key>.*\z/m, "").strip
    return [] if name.empty?

    args = {}
    raw.scan(ARG_KV_PATTERN).each { |k, v| args[k.strip] = v.strip }

    [{
      "id" => "fallback_#{SecureRandom.hex(4)}",
      "type" => "function",
      "function" => { "name" => name, "arguments" => args.to_json }
    }]
  end

  def parse_action_block(content)
    matches = content.scan(ACTION_BLOCK_PATTERN)
    return nil if matches.empty?

    calls = matches.filter_map do |name, body|
      args = JSON.parse(body.strip)
      {
        "id" => "fallback_#{SecureRandom.hex(4)}",
        "type" => "function",
        "function" => { "name" => name.strip, "arguments" => args.to_json }
      }
    rescue JSON::ParserError
      nil
    end
    calls.presence
  end

  def try_parse_bare_tool_call(content)
    calls = content.strip.split("\n").filter_map { |line| parse_single_tool_json(line) }
    calls.presence
  end

  def parse_single_tool_json(line)
    line = line.strip
    return nil if line.empty?
    parsed = JSON.parse(line)
    return nil unless parsed.is_a?(Hash) && parsed["name"].present? && parsed.key?("arguments")
    {
      "id" => "fallback_#{SecureRandom.hex(4)}",
      "type" => "function",
      "function" => {
        "name" => parsed["name"],
        "arguments" => parsed["arguments"].is_a?(String) ? parsed["arguments"] : parsed["arguments"].to_json
      }
    }
  rescue JSON::ParserError
    nil
  end
end
```

Then in `app/services/line/llm_service.rb`:
1. Delete the constants `TOOL_CALL_PATTERN`, `ACTION_BLOCK_PATTERN`, `ARG_KV_PATTERN` and the private methods `parse_tool_calls_from_content`, `build_calls_from_matches`, `parse_arg_kv_tool_call`, `parse_action_block`, `try_parse_bare_tool_call`, `parse_single_tool_json` (everything from the `# Fallback parser for tool calls embedded in content...` comment to the end of the class, keeping the final `end`).
2. In `run_rounds`, replace:

```ruby
        parsed = parse_tool_calls_from_content(assistant_message["content"].to_s)
```

with:

```ruby
        parsed = Line::ToolCallParser.parse(assistant_message["content"].to_s)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tool_call_parser_test.rb test/services/line/llm_service_test.rb`
Expected: PASS (all). The llm_service tests exercise the tool-call loop and must still pass with the extracted parser.

- [ ] **Step 5: Commit**

```bash
hg add app/services/line/tool_call_parser.rb test/services/line/tool_call_parser_test.rb
hg commit app/services/line/tool_call_parser.rb test/services/line/tool_call_parser_test.rb app/services/line/llm_service.rb -m "Extract content tool-call parser from LlmService into Line::ToolCallParser

The upcoming llm:eval harness must score tool calls that models (notably
GLM) embed in message content instead of the structured tool_calls array,
and it must do so exactly the way production does — a private copy would
drift. The parser was six private methods inside LlmService.

Moved verbatim into a Line::ToolCallParser module (module_function); LlmService
now delegates. Behavior unchanged; dedicated parser unit tests added."
```

---

### Task 2: Thread the calling user through ToolExecutor and all handlers

**Files:**
- Modify: `app/services/line/tool_executor.rb`
- Modify: `app/services/line/llm_service.rb` (one line)
- Modify (signature only, one line each): `app/services/line/tools/echo_tool.rb`, `student_lookup_tool.rb`, `staff_lookup_tool.rb`, `course_lookup_tool.rb`, `course_offering_lookup_tool.rb`, `search_tool.rb`, `grade_distribution_tool.rb`, `cohort_gpa_tool.rb`
- Test: `test/services/line/tool_executor_test.rb` (add one test)

**Interfaces:**
- Consumes: `Line::ToolRegistry.handler_for(name)`.
- Produces: `Line::ToolExecutor.execute(tool_calls, user: nil)`; every handler responds to `call(arguments, user: nil)`. All later tool tasks use this signature.

- [ ] **Step 1: Write the failing test**

Add to `test/services/line/tool_executor_test.rb` (inside the class):

```ruby
  test "execute passes user to handlers" do
    probe = Class.new do
      class << self
        attr_accessor :received_user

        def call(_arguments, user: nil)
          self.received_user = user
          "ok"
        end
      end
    end
    Line::ToolRegistry.register("probe_tool",
      definition: { description: "probe", parameters: { type: "object", properties: {} } },
      handler: probe)

    user = User.new(name: "probe user")
    Line::ToolExecutor.execute(
      [ { "id" => "call_1", "function" => { "name" => "probe_tool", "arguments" => "{}" } } ],
      user: user
    )

    assert_same user, probe.received_user
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/line/tool_executor_test.rb`
Expected: FAIL — `ArgumentError: unknown keyword: :user` (execute doesn't accept it yet).

- [ ] **Step 3: Implement**

In `app/services/line/tool_executor.rb` change the two method signatures and the handler call:

```ruby
  def self.execute(tool_calls, user: nil)
    tool_calls.map do |tool_call|
      name = tool_call.dig("function", "name")
      raw_args = tool_call.dig("function", "arguments")
      call_id = tool_call["id"]

      result = invoke(name, raw_args, user)

      { role: "tool", tool_call_id: call_id, content: result.to_s }
    end
  end

  def self.invoke(name, raw_args, user)
```

and inside `invoke`, change `result = handler.call(arguments)` to:

```ruby
    result = handler.call(arguments, user: user)
```

In `app/services/line/llm_service.rb` (`run_rounds`), change:

```ruby
      tool_results = Line::ToolExecutor.execute(tool_calls)
```

to:

```ruby
      tool_results = Line::ToolExecutor.execute(tool_calls, user: @user)
```

In each of the 8 tool files, change the `call` signature only. Example (`echo_tool.rb`); apply identically to all 8:

```ruby
  def self.call(arguments, user: nil)
```

(`user:` is intentionally unused for now — it is the authorization hook for when students get LINE access. Do NOT add `_user` naming; the keyword name is part of the interface.)

Also update the failing-handler stub inside `tool_executor_test.rb` (test "execute logs error when handler raises") so its signature matches:

```ruby
    failing_handler = Class.new do
      def self.call(_args, user: nil)
        raise "something broke"
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/`
Expected: PASS (executor, llm_service, commands, and all tool tests — existing tool tests call `.call(args)` which still works because `user:` defaults to nil).

- [ ] **Step 5: Commit**

```bash
hg commit app/services/line/tool_executor.rb app/services/line/llm_service.rb app/services/line/tools test/services/line/tool_executor_test.rb -m "Thread the calling user through ToolExecutor to all LINE tools

Tools currently receive no user context, so per-user authorization is
impossible — fine while only staff are linked, but the department plans to
eventually give students LINE access, and a student must not be able to
query other students' grades. Plumbing the user through now means future
authorization is a per-tool check, not an infrastructure change.

ToolExecutor.execute takes user: and passes it to every handler; handler
signature is now call(arguments, user: nil). No authorization behavior
changes — all tools remain staff-permissive."
```

---

### Task 3: Retire the echo tool

Echo was the dev scaffold for the tool loop; it burns registry space (every tool definition is sent with every request) and its job is done. Tests that used it get local stub handlers.

**Files:**
- Delete: `app/services/line/tools/echo_tool.rb`
- Modify: `config/initializers/line_tools.rb` (remove echo registration)
- Modify: `test/services/line/tool_executor_test.rb`, `test/services/line/llm_service_test.rb` (local stubs)

**Interfaces:**
- Produces: registry without `echo` (7 tools). `Line::Tools::EchoTool` no longer exists — nothing may reference it.

- [ ] **Step 1: Find all references**

Run: `grep -rn "EchoTool\|\"echo\"" app config test lib docs --include="*.rb" --include="*.haml"`
Expected hits: `config/initializers/line_tools.rb`, `app/services/line/tools/echo_tool.rb`, `test/services/line/tool_executor_test.rb`, `test/services/line/llm_service_test.rb`. If other code references appear, update them the same way (local stub or removal).

- [ ] **Step 2: Remove tool + registration**

```bash
hg remove app/services/line/tools/echo_tool.rb
```

In `config/initializers/line_tools.rb` delete the block:

```ruby
  Line::ToolRegistry.register(
    "echo",
    definition: Line::Tools::EchoTool::DEFINITION,
    handler: Line::Tools::EchoTool
  )
```

- [ ] **Step 3: Replace test usages with local stubs**

In `test/services/line/tool_executor_test.rb`, add a stub class above the test class and change the `setup` block (it currently re-registers `Line::Tools::EchoTool`):

```ruby
# Local stand-in for the retired echo tool: returns its arguments as JSON,
# which is exactly what the executor tests assert on.
class ToolExecutorStubEcho
  def self.call(arguments, user: nil)
    arguments.to_json
  end
end

class Line::ToolExecutorTest < ActiveSupport::TestCase
  setup do
    Line::ToolRegistry.register("echo",
      definition: { description: "test echo", parameters: { type: "object", properties: { text: { type: "string" } } } },
      handler: ToolExecutorStubEcho)
  end
```

(The registered *name* stays `"echo"` so none of the existing assertions change.)

In `test/services/line/llm_service_test.rb`, the setup registers `Line::Tools::EchoTool` the same way — replace the handler with an identical local stub class (`LlmServiceStubEcho`, same body as above) and keep the registered name `"echo"`.

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/line/ && bin/rails runner "puts Line::ToolRegistry.definitions.map { |d| d.dig(:function, :name) }.sort.join(', ')"`
Expected: PASS; runner prints the 7 real tools: `cohort_gpa, course_lookup, course_offering_lookup, grade_distribution, search, staff_lookup, student_lookup` (no echo).

- [ ] **Step 5: Commit**

```bash
hg commit app/services/line/tools/echo_tool.rb config/initializers/line_tools.rb test/services/line/tool_executor_test.rb test/services/line/llm_service_test.rb -m "Retire the echo tool

Echo was scaffolding for bringing up the tool-calling loop. Every
registered tool definition is sent to the model on every request and adds
a selection choice, so a do-nothing tool has ongoing cost and zero value —
and this round is about to grow the registry, making dead weight worth
shedding first.

Removed the tool and its registration; executor/llm_service tests now use
local stub handlers under the same registered name."
```

---

### Task 4: Candidate tool definitions (stub classes)

The four new tools' `DEFINITION` constants must exist **before** implementation so the eval harness can measure the candidate registry (Task 7 gate). Classes are complete on the definition side; `call` raises until Tasks 9–12 implement them. They are NOT registered in the initializer yet.

**Files:**
- Create: `app/services/line/tools/student_grades_tool.rb`
- Create: `app/services/line/tools/course_enrollment_tool.rb`
- Create: `app/services/line/tools/semester_overview_tool.rb`
- Create: `app/services/line/tools/room_schedule_tool.rb`

**Interfaces:**
- Produces: `Line::Tools::StudentGradesTool::DEFINITION` (etc.) consumed by Task 5's RegistryBuilder. Tool names: `student_grades`, `course_enrollment`, `semester_overview`, `room_schedule`.

- [ ] **Step 1: Create the four stub files**

`app/services/line/tools/student_grades_tool.rb`:

```ruby
# Per-term academic record for ONE student: courses + grades per semester,
# term GPA, and cumulative GPAX. The LINE-shaped version of the student show
# page's course history. Chula transcript naming: GPA = semester, GPAX =
# cumulative.
class Line::Tools::StudentGradesTool
  DEFINITION = {
    description: "Get one student's academic record term by term: the courses they took with grades, " \
                 "the semester GPA, and the cumulative GPAX (Chula convention: GPA = semester, " \
                 "GPAX = cumulative; term labels are Buddhist Era like '2567/1'). " \
                 "Use for questions like 'how did student X perform?', 'grades of 6530200321', " \
                 "'is X improving?', or 'did X take course Y?'. Search by student ID or name. " \
                 "For a student's profile without grades use student_lookup instead.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Student ID (e.g. '6530200321') or part of a name (Thai or English). Required."
        },
        semester: {
          type: "string",
          description: "Term in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2567/2'. Omit for all terms."
        }
      },
      required: [ "query" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    raise NotImplementedError, "student_grades is not implemented yet (eval-only definition)"
  end
end
```

`app/services/line/tools/course_enrollment_tool.rb`:

```ruby
# Enrollment for one course in one year/term: totals and a program × cohort
# breakdown, plus an optional point check for a single student. Counts are
# Grade rows aggregated across ALL curriculum revisions of the course_no
# (same revision-insensitive convention as grade_distribution).
class Line::Tools::CourseEnrollmentTool
  DEFINITION = {
    description: "Get enrollment for a course in an academic year (optionally one semester): how many " \
                 "students took it, broken down by program and admission cohort — and optionally check " \
                 "whether one specific student is enrolled. Counts combine all curriculum revisions. " \
                 "Use for 'how many students take X?', 'which programs take X?', or " \
                 "'did student S enroll in X?'. For counts per grade (A/B+/...) use grade_distribution.",
    parameters: {
      type: "object",
      properties: {
        course_no: {
          type: "string",
          description: "Course number, e.g. '2110327'. Required."
        },
        year: {
          type: "integer",
          description: "Academic year. Buddhist Era (e.g. 2568) or Christian Era (e.g. 2025) accepted; " \
                       "values below 2400 are treated as C.E. Required."
        },
        semester: {
          type: "integer",
          description: "Semester: 1, 2, or 3 (summer). Omit for the whole year."
        },
        student_query: {
          type: "string",
          description: "Student ID or name — check whether this one student is enrolled instead of counting everyone."
        }
      },
      required: [ "course_no", "year" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    raise NotImplementedError, "course_enrollment is not implemented yet (eval-only definition)"
  end
end
```

`app/services/line/tools/semester_overview_tool.rb`:

```ruby
# Summary of one semester's teaching schedule: offering / section / distinct
# course counts and a per-program breakdown. Answers "how many courses are
# offered?" — the per-course view is course_offering_lookup.
class Line::Tools::SemesterOverviewTool
  DEFINITION = {
    description: "Overview of one semester's teaching schedule: how many course offerings, sections, and " \
                 "distinct courses are offered, broken down by program. Use for 'how many courses are " \
                 "offered in 2568/1?' or 'what does this semester look like?'. Defaults to the latest " \
                 "semester. For one specific course's sections use course_offering_lookup.",
    parameters: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "Semester in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2568/1'. Omit for the latest semester."
        }
      },
      required: []
    }
  }.freeze

  def self.call(arguments, user: nil)
    raise NotImplementedError, "semester_overview is not implemented yet (eval-only definition)"
  end
end
```

`app/services/line/tools/room_schedule_tool.rb`:

```ruby
# Weekly class schedule of one room for a semester, mirroring the room
# report (SchedulesController#room) as compact JSON.
class Line::Tools::RoomScheduleTool
  DEFINITION = {
    description: "Get a room's weekly class schedule for a semester: which courses/sections meet there, " \
                 "on which days and times, and who teaches. Use for 'what's in room ENG4-303?' or " \
                 "'is room X free on Tuesday?'. Search by room name ('ENG4-303'), building ('ENG4'), " \
                 "or room number ('303'). Defaults to the latest semester. " \
                 "To find where a COURSE meets, use course_offering_lookup instead.",
    parameters: {
      type: "object",
      properties: {
        room: {
          type: "string",
          description: "Room name ('ENG4-303'), building ('ENG4'), or room number ('303'). Required."
        },
        semester: {
          type: "string",
          description: "Semester in 'YEAR/NUMBER' Buddhist-Era format, e.g. '2568/1'. Omit for the latest semester."
        },
        day: {
          type: "string",
          description: "Optional weekday filter, English name or abbreviation, e.g. 'Tuesday' or 'Tue'."
        }
      },
      required: [ "room" ]
    }
  }.freeze

  def self.call(arguments, user: nil)
    raise NotImplementedError, "room_schedule is not implemented yet (eval-only definition)"
  end
end
```

- [ ] **Step 2: Sanity check**

Run: `bin/rails runner "puts [Line::Tools::StudentGradesTool, Line::Tools::CourseEnrollmentTool, Line::Tools::SemesterOverviewTool, Line::Tools::RoomScheduleTool].map { |k| k::DEFINITION[:parameters][:required].inspect }.join(\"\n\")"`
Expected output:

```
["query"]
["course_no", "year"]
[]
["room"]
```

- [ ] **Step 3: Commit**

```bash
hg add app/services/line/tools/student_grades_tool.rb app/services/line/tools/course_enrollment_tool.rb app/services/line/tools/semester_overview_tool.rb app/services/line/tools/room_schedule_tool.rb
hg commit app/services/line/tools/student_grades_tool.rb app/services/line/tools/course_enrollment_tool.rb app/services/line/tools/semester_overview_tool.rb app/services/line/tools/room_schedule_tool.rb -m "Add definition-only stubs for the four round-2 LINE tools

The eval harness gates this round: the candidate tool registry must be
measurable for tool-selection accuracy BEFORE the handlers are built, so
a failed gate costs tool descriptions, not implementations. Eval scoring
is selection-only — definitions are all it needs.

Four Line::Tools classes with complete DEFINITIONs (student_grades,
course_enrollment, semester_overview, room_schedule); call raises
NotImplementedError; not registered in the initializer yet."
```

---

### Task 5: Eval cases, decoy pool, Scorer, RegistryBuilder

**Files:**
- Create: `test/llm_eval/cases.yml`
- Create: `test/llm_eval/decoy_tools.yml`
- Create: `app/services/llm_eval/scorer.rb`
- Create: `app/services/llm_eval/registry_builder.rb`
- Test: `test/services/llm_eval/scorer_test.rb`, `test/services/llm_eval/registry_builder_test.rb`

**Interfaces:**
- Consumes: `Line::ToolRegistry.definitions`, the four `DEFINITION` constants from Task 4.
- Produces:
  - `LlmEval::Scorer.score(eval_case, tool_call) → { called_tool:, tool_ok:, params_ok:, misses: }` — `eval_case` is one parsed YAML hash (string keys); `tool_call` is an OpenAI-format hash or nil.
  - `LlmEval::RegistryBuilder.build(variant, decoy_count: 0) → Array<Hash>` — OpenAI tools array; variants `"current"` and `"candidate"`.
- Case YAML schema: `id`, `group` (`existing` | `new` | `none`), `question`, `accept:` — list of `{tool:, params:}` alternatives; a call passes if it matches ANY alternative. `tool: none` means "no tool call is the right answer". Param matching: expected **string** values pass when the actual value *contains* them case-insensitively (models legitimately send `"อ.ณัฐ"` where we expect `"ณัฐ"`); non-strings compare as normalized strings (YAML `2568` matches JSON `"2568"`).

- [ ] **Step 1: Write failing scorer test**

Create `test/services/llm_eval/scorer_test.rb`:

```ruby
require "test_helper"

class LlmEval::ScorerTest < ActiveSupport::TestCase
  CASE_SINGLE = {
    "id" => "t1", "group" => "existing", "question" => "q",
    "accept" => [ { "tool" => "student_lookup", "params" => { "query" => "6732100021" } } ]
  }.freeze

  CASE_MULTI = {
    "id" => "t2", "group" => "new", "question" => "q",
    "accept" => [
      { "tool" => "course_enrollment", "params" => { "course_no" => "2110499" } },
      { "tool" => "student_grades", "params" => { "query" => "6732100021" } }
    ]
  }.freeze

  CASE_NONE = {
    "id" => "t3", "group" => "none", "question" => "q",
    "accept" => [ { "tool" => "none" } ]
  }.freeze

  def tool_call(name, args)
    { "id" => "c1", "function" => { "name" => name, "arguments" => args.to_json } }
  end

  test "exact tool and params pass" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("student_lookup", { query: "6732100021" }))
    assert s[:tool_ok]
    assert s[:params_ok]
    assert_equal [], s[:misses]
  end

  test "string params match by case-insensitive containment" do
    kase = { "accept" => [ { "tool" => "staff_lookup", "params" => { "query" => "ณัฐ" } } ] }
    s = LlmEval::Scorer.score(kase, tool_call("staff_lookup", { query: "อ.ณัฐ" }))
    assert s[:params_ok]
  end

  test "integer expected matches string actual" do
    kase = { "accept" => [ { "tool" => "cohort_gpa", "params" => { "admission_year" => 2565 } } ] }
    s = LlmEval::Scorer.score(kase, tool_call("cohort_gpa", { admission_year: "2565" }))
    assert s[:params_ok]
  end

  test "wrong tool fails" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("search", { query: "6732100021" }))
    refute s[:tool_ok]
    assert_equal "search", s[:called_tool]
  end

  test "missing param is reported" do
    s = LlmEval::Scorer.score(CASE_SINGLE, tool_call("student_lookup", { program_code: "CP" }))
    assert s[:tool_ok]
    refute s[:params_ok]
    assert_equal [ "query" ], s[:misses]
  end

  test "any accept alternative passes" do
    s = LlmEval::Scorer.score(CASE_MULTI, tool_call("student_grades", { query: "6732100021" }))
    assert s[:tool_ok]
    assert s[:params_ok]
  end

  test "nil tool_call scores as none" do
    s = LlmEval::Scorer.score(CASE_NONE, nil)
    assert s[:tool_ok]
    assert s[:params_ok]

    s2 = LlmEval::Scorer.score(CASE_SINGLE, nil)
    refute s2[:tool_ok]
    assert_equal "none", s2[:called_tool]
  end

  test "unparseable arguments JSON fails params but not tool" do
    call = { "id" => "c1", "function" => { "name" => "student_lookup", "arguments" => "not json" } }
    s = LlmEval::Scorer.score(CASE_SINGLE, call)
    assert s[:tool_ok]
    refute s[:params_ok]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/llm_eval/scorer_test.rb`
Expected: FAIL — `NameError: uninitialized constant LlmEval`

- [ ] **Step 3: Implement Scorer**

Create `app/services/llm_eval/scorer.rb`:

```ruby
module LlmEval
  # Scores one model attempt against an eval case's accepted alternatives.
  # A case passes on tool selection when the called tool matches ANY accept
  # alternative; params are then checked against that alternative only.
  class Scorer
    def self.score(eval_case, tool_call)
      called = tool_call ? tool_call.dig("function", "name") : "none"
      args = extract_args(tool_call)

      eval_case["accept"].each do |alt|
        next unless alt["tool"] == called

        misses = (alt["params"] || {}).reject { |key, expected| param_match?(args[key], expected) }.keys
        return { called_tool: called, tool_ok: true, params_ok: misses.empty?, misses: misses }
      end

      { called_tool: called, tool_ok: false, params_ok: false, misses: [] }
    end

    def self.extract_args(tool_call)
      return {} unless tool_call

      raw = tool_call.dig("function", "arguments")
      raw.is_a?(String) ? JSON.parse(raw) : (raw || {})
    rescue JSON::ParserError
      {}
    end
    private_class_method :extract_args

    # Strings pass on case-insensitive CONTAINMENT — models legitimately send
    # "อ.ณัฐ" where the case expects "ณัฐ", or "ENG4-303" for "303". Non-strings
    # compare as normalized strings so YAML 2568 matches JSON "2568".
    def self.param_match?(actual, expected)
      return false if actual.nil?

      if expected.is_a?(String)
        actual.to_s.downcase.include?(expected.downcase)
      else
        actual.to_s.strip == expected.to_s
      end
    end
    private_class_method :param_match?
  end
end
```

- [ ] **Step 4: Run scorer test — PASS. Write failing RegistryBuilder test**

Run: `bin/rails test test/services/llm_eval/scorer_test.rb` → PASS.

Create `test/services/llm_eval/registry_builder_test.rb`:

```ruby
require "test_helper"

class LlmEval::RegistryBuilderTest < ActiveSupport::TestCase
  test "current variant returns the live registry" do
    defs = LlmEval::RegistryBuilder.build("current")
    assert_equal Line::ToolRegistry.definitions.size, defs.size
    assert_includes defs.map { |d| d.dig(:function, :name) }, "student_lookup"
  end

  test "candidate variant adds the four round-2 tools" do
    names = LlmEval::RegistryBuilder.build("candidate").map { |d| d.dig(:function, :name) }
    %w[student_grades course_enrollment semester_overview room_schedule].each do |tool|
      assert_includes names, tool
    end
    assert_equal names.uniq.size, names.size, "no duplicate tool names"
  end

  test "candidate variant skips tools that are already registered" do
    Line::ToolRegistry.register("student_grades",
      definition: Line::Tools::StudentGradesTool::DEFINITION,
      handler: Line::Tools::StudentGradesTool)
    names = LlmEval::RegistryBuilder.build("candidate").map { |d| d.dig(:function, :name) }
    assert_equal 1, names.count("student_grades")
  ensure
    Line::ToolRegistry.reset!
    Rails.application.reloader.reload!
  end

  test "decoy_count pads with decoys in OpenAI format" do
    base = LlmEval::RegistryBuilder.build("candidate")
    padded = LlmEval::RegistryBuilder.build("candidate", decoy_count: 5)
    assert_equal base.size + 5, padded.size

    decoy = padded.last
    assert_equal "function", decoy[:type]
    assert decoy.dig(:function, :name).present?
    assert decoy.dig(:function, :description).present?
    assert decoy.dig(:function, :parameters).present?
  end

  test "unknown variant raises" do
    assert_raises(ArgumentError) { LlmEval::RegistryBuilder.build("bogus") }
  end
end
```

Note the `ensure` block: `ToolRegistry.reset!` wipes the registry, and `reload!` re-runs `to_prepare` to restore the real registrations for subsequent tests.

Run: `bin/rails test test/services/llm_eval/registry_builder_test.rb` → FAIL (`uninitialized constant LlmEval::RegistryBuilder`).

- [ ] **Step 5: Implement RegistryBuilder + decoys**

Create `app/services/llm_eval/registry_builder.rb`:

```ruby
module LlmEval
  # Builds the OpenAI tools array for an eval variant:
  #   "current"   — exactly what ToolRegistry has registered (production view)
  #   "candidate" — current + the round-2 definitions not yet registered
  # decoy_count pads with definition-only fake tools from decoy_tools.yml for
  # the breaking-point sweep (accuracy vs. registry size).
  class RegistryBuilder
    CANDIDATE_TOOLS = {
      "student_grades"    => "Line::Tools::StudentGradesTool",
      "course_enrollment" => "Line::Tools::CourseEnrollmentTool",
      "semester_overview" => "Line::Tools::SemesterOverviewTool",
      "room_schedule"     => "Line::Tools::RoomScheduleTool"
    }.freeze

    DECOY_FILE = "test/llm_eval/decoy_tools.yml"

    def self.build(variant, decoy_count: 0)
      defs =
        case variant
        when "current"
          Line::ToolRegistry.definitions
        when "candidate"
          registered = Line::ToolRegistry.definitions
          registered_names = registered.map { |d| d.dig(:function, :name) }
          extra = CANDIDATE_TOOLS.reject { |name, _| registered_names.include?(name) }
          registered + extra.map { |name, klass| wrap(name, klass.constantize::DEFINITION) }
        else
          raise ArgumentError, "unknown registry variant '#{variant}' (use current|candidate)"
        end

      defs + decoys.first(decoy_count).map { |d| wrap(d["name"], d.except("name").deep_symbolize_keys) }
    end

    def self.wrap(name, definition)
      { type: "function", function: { name: name }.merge(definition) }
    end
    private_class_method :wrap

    def self.decoys
      YAML.load_file(Rails.root.join(DECOY_FILE))
    end
    private_class_method :decoys
  end
end
```

Create `test/llm_eval/decoy_tools.yml` (13 decoys; the last four are deliberately *near-overlapping* with real tools — the hard part of the sweep):

```yaml
# Definition-only fake tools used to pad the registry for the breaking-point
# sweep (bin/rails llm:eval SWEEP=1). Never registered, never executed.
# Ordered easy → hard: the first entries are clearly out-of-domain; the last
# four deliberately sit close to real tools to stress selection.
- name: library_search
  description: Search the university library catalog for books, journals, and theses by title, author, or ISBN.
  parameters:
    type: object
    properties:
      query: { type: string, description: "Title, author, or ISBN to search for." }
    required: [query]
- name: payroll_lookup
  description: Look up salary payment records and payslip history for an employee by ID.
  parameters:
    type: object
    properties:
      employee_id: { type: string, description: Employee ID. }
      month: { type: string, description: "Month in YYYY-MM format." }
    required: [employee_id]
- name: leave_request
  description: Submit or check the status of a staff annual/sick leave request.
  parameters:
    type: object
    properties:
      staff_id: { type: string, description: Staff ID. }
      status_only: { type: boolean, description: Only check status of existing requests. }
    required: [staff_id]
- name: parking_availability
  description: Check available parking spots per building parking lot on campus.
  parameters:
    type: object
    properties:
      building: { type: string, description: Building name. }
    required: []
- name: print_queue_status
  description: Check the department print server queue and printer toner levels.
  parameters:
    type: object
    properties:
      printer: { type: string, description: Printer name. }
    required: []
- name: it_ticket_lookup
  description: Look up IT helpdesk tickets by ticket number or reporter name.
  parameters:
    type: object
    properties:
      query: { type: string, description: Ticket number or reporter name. }
    required: [query]
- name: inventory_lookup
  description: Search department equipment inventory by asset tag or equipment name.
  parameters:
    type: object
    properties:
      query: { type: string, description: Asset tag or equipment name. }
    required: [query]
- name: shuttle_schedule
  description: Get the campus shuttle bus timetable between buildings and gates.
  parameters:
    type: object
    properties:
      route: { type: string, description: Route name or number. }
    required: []
- name: cafeteria_menu
  description: Get today's menu for campus cafeterias.
  parameters:
    type: object
    properties:
      cafeteria: { type: string, description: Cafeteria name. }
    required: []
# --- near-overlap decoys: close to real tools on purpose ---
- name: meeting_room_booking
  description: Book or check availability of department MEETING rooms for staff meetings (not classrooms or class schedules).
  parameters:
    type: object
    properties:
      room: { type: string, description: Meeting room name. }
      date: { type: string, description: "Date in YYYY-MM-DD." }
    required: []
- name: thesis_defense_schedule
  description: Look up graduate thesis defense appointments by student or examiner (not regular class schedules).
  parameters:
    type: object
    properties:
      query: { type: string, description: Student or examiner name. }
    required: [query]
- name: alumni_lookup
  description: Search the alumni association directory by name or graduation year (not current student records).
  parameters:
    type: object
    properties:
      query: { type: string, description: Alumni name. }
      graduation_year: { type: integer, description: Graduation year (B.E.). }
    required: []
- name: admission_stats
  description: Get APPLICANT statistics for admission rounds - applications received per round (not enrolled student counts).
  parameters:
    type: object
    properties:
      year: { type: integer, description: Admission year (B.E.). }
      round: { type: string, description: "TCAS round, e.g. 'TCAS1'." }
    required: [year]
```

- [ ] **Step 6: Create the case set**

Create `test/llm_eval/cases.yml` (42 cases; Thai/English mix; `group` drives per-group reporting):

```yaml
# Tool-selection eval cases for bin/rails llm:eval.
# Schema per case:
#   id       — unique slug
#   group    — existing | new | none  (reporting buckets; gate applies per group)
#   question — the user message, verbatim
#   accept   — alternatives; the attempt passes tool selection when the called
#              tool matches ANY entry. params are a SUBSET check against that
#              entry (strings: case-insensitive containment; ints: normalized).
#              tool: none = correct answer is NO tool call.
# Data referenced here does not need to exist — eval never executes tools.

# ---- student_lookup (existing) ----
- id: student_by_id
  group: existing
  question: "ขอข้อมูลนิสิต 6732100021"
  accept:
    - tool: student_lookup
      params: { query: "6732100021" }
- id: student_by_name_en
  group: existing
  question: "Find the student named Thanawat"
  accept:
    - tool: student_lookup
      params: { query: "Thanawat" }
    - tool: search
      params: { query: "Thanawat" }
- id: student_count_cohort
  group: existing
  question: "How many CP students were admitted in 2567?"
  accept:
    - tool: student_lookup
      params: { program_code: "CP", admission_year: 2567 }
- id: student_count_th
  group: existing
  question: "นิสิต CEDT รุ่นปี 2568 มีกี่คน"
  accept:
    - tool: student_lookup
      params: { program_code: "CEDT", admission_year: 2568 }
- id: student_status_filter
  group: existing
  question: "List CP students who are currently on leave"
  accept:
    - tool: student_lookup
      params: { program_code: "CP", status: "on_leave" }

# ---- staff_lookup (existing; also covers workload after Task 13) ----
- id: staff_by_initials
  group: existing
  question: "Who is staff JS?"
  accept:
    - tool: staff_lookup
      params: { query: "JS" }
    - tool: search
      params: { query: "JS" }
- id: staff_by_name_th
  group: existing
  question: "อ.สมิธ อยู่ภาควิชาโปรแกรมไหน"
  accept:
    - tool: staff_lookup
      params: { query: "สมิธ" }
- id: staff_teaching_th
  group: existing
  question: "อ.สมิธ สอนวิชาอะไรบ้างเทอมนี้"
  accept:
    - tool: staff_lookup
      params: { query: "สมิธ" }
- id: staff_workload_en
  group: existing
  question: "How much teaching load does Prof. Jones have this semester?"
  accept:
    - tool: staff_lookup
      params: { query: "Jones" }
- id: staff_load_th
  group: existing
  question: "ภาระงานสอนของ อ.เจน โจนส์ เป็นเท่าไหร่"
  accept:
    - tool: staff_lookup
      params: { query: "เจน" }

# ---- course_lookup (existing) ----
- id: course_credits_th
  group: existing
  question: "วิชา 2110327 กี่หน่วยกิต"
  accept:
    - tool: course_lookup
      params: { query: "2110327" }
- id: course_by_topic_th
  group: existing
  question: "มีวิชาเกี่ยวกับปัญญาประดิษฐ์ไหม"
  accept:
    - tool: course_lookup
      params: { query: "ปัญญาประดิษฐ์" }
    - tool: search
      params: { query: "ปัญญาประดิษฐ์" }
- id: course_name_en
  group: existing
  question: "What is course 2110101 called in English and how many credits is it?"
  accept:
    - tool: course_lookup
      params: { query: "2110101" }

# ---- course_offering_lookup (existing) ----
- id: offering_who_teaches
  group: existing
  question: "Who teaches 2110101 in semester 2568/1?"
  accept:
    - tool: course_offering_lookup
      params: { course_no: "2110101", semester: "2568/1" }
- id: offering_sections_th
  group: existing
  question: "2110327 มีกี่เซค ใครสอนเซคไหนบ้าง"
  accept:
    - tool: course_offering_lookup
      params: { course_no: "2110327" }
- id: offering_schedule_en
  group: existing
  question: "When does 2110499 meet this semester?"
  accept:
    - tool: course_offering_lookup
      params: { course_no: "2110499" }
- id: offering_room_of_course
  group: existing
  question: "วิชา 2110101 เรียนห้องไหน"
  accept:
    - tool: course_offering_lookup
      params: { course_no: "2110101" }

# ---- grade_distribution (existing) ----
- id: grade_dist_en
  group: existing
  question: "Show the grade distribution for 2110327 in year 2567"
  accept:
    - tool: grade_distribution
      params: { course_no: "2110327", year: 2567 }
- id: grade_dist_th
  group: existing
  question: "วิชา 2110101 ปี 2567 เทอม 1 มีคนได้ A กี่คน"
  accept:
    - tool: grade_distribution
      params: { course_no: "2110101", year: 2567, semester: 1 }
- id: course_gpa_term
  group: existing
  question: "What was the average grade of 2110203 in 2566/2?"
  accept:
    - tool: grade_distribution
      params: { course_no: "2110203", year: 2566, semester: 2 }
- id: grade_dist_fail_count
  group: existing
  question: "How many students failed 2110203 in 2566?"
  accept:
    - tool: grade_distribution
      params: { course_no: "2110203", year: 2566 }

# ---- cohort_gpa (existing) ----
- id: cohort_gpa_en
  group: existing
  question: "What's the average GPA of the CP 2565 cohort?"
  accept:
    - tool: cohort_gpa
      params: { program_code: "CP", admission_year: 2565 }
- id: cohort_gpax_th
  group: existing
  question: "GPAX เฉลี่ยของ CEDT รุ่น 2566 เป็นเท่าไหร่"
  accept:
    - tool: cohort_gpa
      params: { program_code: "CEDT", admission_year: 2566 }
- id: cohort_trend
  group: existing
  question: "How has the CP 2564 cohort's GPA developed semester by semester?"
  accept:
    - tool: cohort_gpa
      params: { program_code: "CP", admission_year: 2564 }

# ---- search (existing) ----
- id: search_bare_name
  group: existing
  question: "สมิธ"
  accept:
    - tool: search
      params: { query: "สมิธ" }
    - tool: staff_lookup
      params: { query: "สมิธ" }
    - tool: student_lookup
      params: { query: "สมิธ" }
- id: search_ambiguous_number
  group: existing
  question: "2110"
  accept:
    - tool: search
      params: { query: "2110" }
    - tool: course_lookup
      params: { query: "2110" }

# ---- no tool (none) ----
- id: none_greeting
  group: none
  question: "สวัสดีครับ"
  accept:
    - tool: none
- id: none_general_knowledge
  group: none
  question: "What is the capital of France?"
  accept:
    - tool: none

# ---- student_grades (new) ----
- id: transcript_all_terms
  group: new
  question: "How did student 6532100071 perform over the years?"
  accept:
    - tool: student_grades
      params: { query: "6532100071" }
- id: transcript_one_term_th
  group: new
  question: "เกรดของนิสิต 6732100021 เทอม 2567/2 เป็นยังไงบ้าง"
  accept:
    - tool: student_grades
      params: { query: "6732100021", semester: "2567/2" }
- id: transcript_by_name_th
  group: new
  question: "ผลการเรียนของธนวัฒน์ ศรีเจริญ ดูหน่อย"
  accept:
    - tool: student_grades
      params: { query: "ธนวัฒน์" }
- id: transcript_improving
  group: new
  question: "Is student 6632100063 improving or getting worse each semester?"
  accept:
    - tool: student_grades
      params: { query: "6632100063" }
- id: gpa_of_student_ambiguous
  group: new
  question: "GPA ของนิสิต 6532100071 เป็นเท่าไหร่"
  accept:
    - tool: student_grades
      params: { query: "6532100071" }
    - tool: student_lookup
      params: { query: "6532100071" }

# ---- course_enrollment (new) ----
- id: enrollment_count_en
  group: new
  question: "How many students took 2110101 in 2567?"
  accept:
    - tool: course_enrollment
      params: { course_no: "2110101", year: 2567 }
- id: enrollment_breakdown_th
  group: new
  question: "วิชา 2110327 ปี 2568 เทอม 1 มีนิสิตภาคไหนเรียนบ้าง อย่างละกี่คน"
  accept:
    - tool: course_enrollment
      params: { course_no: "2110327", year: 2568, semester: 1 }
- id: enrollment_membership
  group: new
  question: "Did student 6732100021 enroll in 2110499 in 2567?"
  accept:
    - tool: course_enrollment
      params: { course_no: "2110499", year: 2567, student_query: "6732100021" }
    - tool: student_grades
      params: { query: "6732100021" }

# ---- semester_overview (new) ----
- id: overview_named_term
  group: new
  question: "How many courses are offered in semester 2568/1?"
  accept:
    - tool: semester_overview
      params: { semester: "2568/1" }
- id: overview_current_th
  group: new
  question: "เทอมนี้เปิดสอนกี่วิชา กี่เซค"
  accept:
    - tool: semester_overview
- id: overview_year_term_th
  group: new
  question: "ปีการศึกษา 2567 เทอม 2 มีวิชาเปิดกี่วิชา"
  accept:
    - tool: semester_overview
      params: { semester: "2567/2" }

# ---- room_schedule (new) ----
- id: room_week
  group: new
  question: "What is the class schedule of room ENG4-303 in 2568/1?"
  accept:
    - tool: room_schedule
      params: { room: "303", semester: "2568/1" }
- id: room_day_th
  group: new
  question: "ห้อง ENG4-303 วันอังคารมีเรียนวิชาอะไรบ้าง"
  accept:
    - tool: room_schedule
      params: { room: "303" }
- id: room_free_check
  group: new
  question: "Is room ENG3-201 free on Friday afternoon this semester?"
  accept:
    - tool: room_schedule
      params: { room: "201" }
```

- [ ] **Step 7: Run tests**

Run: `bin/rails test test/services/llm_eval/`
Expected: PASS (scorer + registry builder).

Also validate the YAML loads and case ids are unique:

Run: `bin/rails runner "cases = YAML.load_file('test/llm_eval/cases.yml'); raise 'dup ids' if cases.map { |c| c['id'] }.uniq.size != cases.size; raise 'bad group' if cases.any? { |c| !%w[existing new none].include?(c['group']) }; puts \"#{cases.size} cases OK\""`
Expected: `42 cases OK`

- [ ] **Step 8: Commit**

```bash
hg add app/services/llm_eval test/services/llm_eval test/llm_eval
hg commit app/services/llm_eval test/services/llm_eval test/llm_eval -m "Add eval case set, decoy pool, scorer, and registry builder for llm:eval

Whether the LINE bot's tool registry can grow without hurting tool-selection
accuracy has so far been folklore (docs/llm-data-query.md's 8-10 tool claim
predates the current model lineup). These are the measurement pieces: 42
annotated Thai/English questions with accept-alternatives, 13 decoy tool
definitions (four deliberately near-overlapping) for the breaking-point
sweep, subset param scoring with containment semantics, and registry
variants (current/candidate/padded) built from real DEFINITIONs so eval
never duplicates a tool description."
```

---

### Task 6: Eval runner + `llm:eval` rake task

**Files:**
- Create: `app/services/llm_eval/runner.rb`
- Create: `lib/tasks/llm_eval.rake`

**Interfaces:**
- Consumes: `LlmEval::Scorer.score`, `LlmEval::RegistryBuilder.build`, `Line::ToolCallParser.parse`, `LLM_CONFIG[:models]` / `[:system_prompt]`.
- Produces: `LlmEval::Runner.new(model_key:, definitions:, cases:, repeats:).call → Array<Hash>` where each hash is `{ case_id:, group:, attempt:, called_tool:, tool_ok:, params_ok:, misses: }`. Rake task `llm:eval` with env knobs `MODEL`, `N`, `CASES`, `REGISTRY`, `SWEEP`.

The Runner does live HTTP — no unit test (the scorer and builder carry the logic; the runner is thin transport). Verified by the smoke run in Step 3.

- [ ] **Step 1: Implement Runner**

Create `app/services/llm_eval/runner.rb`:

```ruby
module LlmEval
  # Fires each eval case at a vLLM endpoint and scores the FIRST tool call
  # the model emits. Selection-only: tools are never executed, so candidate
  # definitions can be evaluated before their handlers exist and eval runs
  # can never touch data.
  #
  # Uses the production system prompt and temperature so results reflect
  # what LINE users actually experience; repeats measure sampling variance.
  class Runner
    REQUEST_TEMPERATURE = 0.7 # match LlmService#chat_completion

    def initialize(model_key:, definitions:, cases:, repeats: 3)
      @model_config = LLM_CONFIG[:models][model_key.to_sym] ||
                      raise(ArgumentError, "unknown model '#{model_key}' (keys: #{LLM_CONFIG[:models].keys.join(', ')})")
      @definitions = definitions
      @cases = cases
      @repeats = repeats
    end

    # Yields (result_hash) after each attempt for live progress output.
    def call
      results = []
      @cases.each do |kase|
        @repeats.times do |i|
          result = attempt(kase, i + 1)
          results << result
          yield result if block_given?
        end
      end
      results
    end

    private

    def attempt(kase, attempt_no)
      tool_call =
        begin
          first_tool_call(kase["question"])
        rescue StandardError => e
          return { case_id: kase["id"], group: kase["group"], attempt: attempt_no,
                   called_tool: "ERROR: #{e.class}", tool_ok: false, params_ok: false, misses: [] }
        end

      LlmEval::Scorer.score(kase, tool_call)
             .merge(case_id: kase["id"], group: kase["group"], attempt: attempt_no)
    end

    def first_tool_call(question)
      body = {
        model: @model_config[:model],
        messages: [
          { role: "system", content: LLM_CONFIG[:system_prompt] },
          { role: "user", content: question }
        ],
        temperature: REQUEST_TEMPERATURE,
        max_tokens: @model_config[:max_tokens] || 4096,
        tools: @definitions
      }

      uri = URI("#{@model_config[:base_url]}#{@model_config[:endpoint]}")
      response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 120) do |http|
        http.post(uri, body.to_json, "Content-Type" => "application/json")
      end
      raise "vLLM returned #{response.code}: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)

      message = JSON.parse(response.body).dig("choices", 0, "message") || {}
      tool_calls = message["tool_calls"].presence ||
                   Line::ToolCallParser.parse(message["content"].to_s)
      tool_calls&.first
    end
  end
end
```

- [ ] **Step 2: Implement the rake task**

Create `lib/tasks/llm_eval.rake`:

```ruby
# Tool-selection eval for the LINE chatbot's LLM tools. Selection-only:
# scores which tool the model calls with which params; never executes tools.
#
# Usage:
#   bin/rails llm:eval                            # current registry, qwen, 3 repeats
#   bin/rails llm:eval MODEL=gemma                # other model (keys from config/llm.yml)
#   bin/rails llm:eval REGISTRY=candidate         # current + unregistered round-2 tools
#   bin/rails llm:eval N=5 CASES=room_week,none_greeting
#   bin/rails llm:eval SWEEP=1                    # breaking-point sweep across registry sizes
#
# Output: per-case console table + CSV under tmp/llm_eval/.
desc "Score LLM tool selection against test/llm_eval/cases.yml"
task "llm:eval" => :environment do
  require "csv"

  model = ENV.fetch("MODEL", "qwen")
  repeats = ENV.fetch("N", "3").to_i
  registry = ENV.fetch("REGISTRY", "current")

  cases = YAML.load_file(Rails.root.join("test/llm_eval/cases.yml"))
  if ENV["CASES"].present?
    wanted = ENV["CASES"].split(",").map(&:strip)
    cases = cases.select { |c| wanted.include?(c["id"]) }
    abort "No cases matched CASES=#{ENV['CASES']}" if cases.empty?
  end

  variants =
    if ENV["SWEEP"] == "1"
      # Registry sizes for the accuracy-vs-tool-count curve. With 7 shipped +
      # 4 candidate tools this yields roughly 7 / 11 / 16 / 24 definitions.
      [ [ "current", 0 ], [ "candidate", 0 ], [ "candidate", 5 ], [ "candidate", 13 ] ]
    else
      [ [ registry, 0 ] ]
    end

  timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
  out_dir = Rails.root.join("tmp/llm_eval")
  FileUtils.mkdir_p(out_dir)

  variants.each do |variant, decoy_count|
    definitions = LlmEval::RegistryBuilder.build(variant, decoy_count: decoy_count)
    label = decoy_count.zero? ? variant : "#{variant}+#{decoy_count}decoys"
    puts "", "=== #{label}: #{definitions.size} tools | model=#{model} | #{cases.size} cases × #{repeats} ==="

    runner = LlmEval::Runner.new(model_key: model, definitions: definitions, cases: cases, repeats: repeats)
    results = runner.call do |r|
      status = r[:tool_ok] ? (r[:params_ok] ? "PASS" : "tool-ok/params-MISS #{r[:misses].join(',')}") : "FAIL → #{r[:called_tool]}"
      puts format("  %-28s #%d %s", r[:case_id], r[:attempt], status)
    end

    csv_path = out_dir.join("#{timestamp}-#{model}-#{label}.csv")
    CSV.open(csv_path, "w") do |csv|
      csv << %w[case_id group attempt tool_count called_tool tool_ok params_ok misses]
      results.each do |r|
        csv << [ r[:case_id], r[:group], r[:attempt], definitions.size,
                 r[:called_tool], r[:tool_ok], r[:params_ok], r[:misses].join("|") ]
      end
    end

    puts "-" * 60
    %w[existing new none].each do |group|
      rows = results.select { |r| r[:group] == group }
      next if rows.empty?
      tool_pct = (100.0 * rows.count { |r| r[:tool_ok] } / rows.size).round(1)
      params_pct = (100.0 * rows.count { |r| r[:params_ok] } / rows.size).round(1)
      puts format("  %-10s tool %5.1f%%  tool+params %5.1f%%  (%d attempts)", group, tool_pct, params_pct, rows.size)
    end
    errors = results.count { |r| r[:called_tool].to_s.start_with?("ERROR") }
    puts "  transport errors: #{errors}" if errors.positive?
    puts "  CSV: #{csv_path}"
  end
end
```

- [ ] **Step 3: Smoke test against the live default model**

Run: `bin/rails llm:eval CASES=none_greeting,student_by_id N=1`
Expected: console shows 2 case lines with PASS/FAIL statuses (no exception), a summary block, and a CSV path under `tmp/llm_eval/`. (Requires the DGX endpoint to be reachable; if it isn't, expect `ERROR: ...` rows — the harness itself must still complete and write the CSV.)

- [ ] **Step 4: Commit**

```bash
hg add app/services/llm_eval/runner.rb lib/tasks/llm_eval.rake
hg commit app/services/llm_eval/runner.rb lib/tasks/llm_eval.rake -m "Add llm:eval rake task and runner for live tool-selection scoring

Round 2 adds four tools to the LINE bot, and the only honest way to know
whether the bigger registry hurts the open-weight models is to measure:
fire the annotated question set at the live endpoint, capture the first
tool call (structured or content-embedded, via the shared parser), and
score selection + params. SWEEP=1 pads with decoys at several registry
sizes to chart accuracy vs. tool count per model.

Selection-only by design — tools never execute, so the harness is safe to
run against any environment and works before handlers exist."
```

---

### Task 7: CHECKPOINT — run baseline + candidate + sweep, apply the gate

**This task runs live evals and requires the DGX (qwen) and A100 (gemma) endpoints. It produces numbers, not code. STOP at Step 4 for a human gate decision.**

**Files:**
- Create: `docs/llm-eval-results.md`

- [ ] **Step 1: Run the A/B matrix**

```bash
bin/rails llm:eval MODEL=qwen  N=3
bin/rails llm:eval MODEL=qwen  N=3 REGISTRY=candidate
bin/rails llm:eval MODEL=gemma N=3
bin/rails llm:eval MODEL=gemma N=3 REGISTRY=candidate
```

Note: with 42 cases × 3 repeats this is 126 requests per run (~10–30 min each depending on model speed). Run sequentially; qwen and gemma runs may go in parallel terminals (different machines).

- [ ] **Step 2: Run the sweep**

```bash
bin/rails llm:eval MODEL=qwen  N=2 SWEEP=1
bin/rails llm:eval MODEL=gemma N=2 SWEEP=1
```

- [ ] **Step 3: Record results**

Create `docs/llm-eval-results.md` with the actual numbers from the console summaries / CSVs:

```markdown
# LLM Tool-Selection Eval Results

Selection-only accuracy from `bin/rails llm:eval` (see docs/line-integration.md
for the harness). Gate for registry changes: on qwen, existing-group tool
accuracy within 3 points of baseline AND new-group tool accuracy ≥ 80%.

## 2026-07-XX — round-2 gate (baseline 7 tools vs candidate 11)

| model | registry | tools | existing tool% | existing t+p% | new tool% | new t+p% | none% |
|---|---|---|---|---|---|---|---|
| qwen  | current    | 7  | ... | ... | n/a | n/a | ... |
| qwen  | candidate  | 11 | ... | ... | ... | ... | ... |
| gemma | current    | 7  | ... | ... | n/a | n/a | ... |
| gemma | candidate  | 11 | ... | ... | ... | ... | ... |

(existing-group cases can still be scored under the current registry; new-group
cases are only meaningful under candidate.)

## Breaking-point sweep (N=2)

| model | tools | existing tool% | new tool% |
|---|---|---|---|
| qwen  | 7 / 11 / 16 / 24 | ... | ... |
| gemma | 7 / 11 / 16 / 24 | ... | ... |

Caveat: the padded points depend on decoy quality (see
test/llm_eval/decoy_tools.yml); the curve is indicative, not a universal law.

## Gate decision

- Qwen existing regression: X.X points → PASS/FAIL
- Qwen new-tool accuracy: XX% → PASS/FAIL
- Decision: proceed with Tasks 8–14 / revise descriptions and re-run.
```

Fill in every `...` from the CSVs. Replace `2026-07-XX` with the run date.

- [ ] **Step 4: STOP — human gate review**

Present the table to dae. Gate (from the spec): on **qwen**, candidate existing-group tool accuracy no more than 3 percentage points below baseline, AND new-group tool accuracy ≥ 80%. If the gate fails: revise the failing tools' `DEFINITION` descriptions (Task 4 files), re-run Step 1, update the results doc — do NOT restructure tools without dae's sign-off. Only continue to Task 8 after explicit approval.

- [ ] **Step 5: Commit**

```bash
hg add docs/llm-eval-results.md
hg commit docs/llm-eval-results.md -m "Record round-2 eval gate results (baseline vs candidate + sweep)

The round-2 tool rollout is gated on measured tool-selection accuracy, not
judgment: qwen must hold existing-case accuracy within 3 points of the
7-tool baseline and reach 80% on the new-tool cases. This documents the
numbers behind the go/no-go, plus the accuracy-vs-registry-size sweep that
tells us how much headroom future tool additions have per model."
```

---

### Task 8: `GradeStats::StudentTranscript` service

**Files:**
- Create: `app/services/grade_stats/student_transcript.rb`
- Test: `test/services/grade_stats/student_transcript_test.rb`

**Interfaces:**
- Consumes: `student.grades`, `courses` join (`Grade` fields: `year_ce`, `semester`, `grade`, `grade_weight`; `Course` fields: `course_no`, `name`, `credits`).
- Produces: `GradeStats::StudentTranscript.call(student:) → { terms: [ { year_ce:, semester:, courses: [ { course_no:, name:, credits:, grade: } ], gpa:, gpax: } ] }` — terms ascending; GPA/GPAX rounded to 2 decimals; nil when a term has no weighted grades. Consumed by Task 9.

- [ ] **Step 1: Write the failing test**

Create `test/services/grade_stats/student_transcript_test.rb`:

```ruby
require "test_helper"

class GradeStats::StudentTranscriptTest < ActiveSupport::TestCase
  # Isolated records (course_no 997xxxx, student id 99xxx) — same convention
  # as cohort_gpa_tool_test — so fixture grades don't disturb the math.
  setup do
    @student = Student.create!(student_id: "9900000801", first_name: "T", last_name: "S",
                               first_name_th: "ท", last_name_th: "ส",
                               admission_year_be: 2599, status: "active",
                               program: programs(:cp_bachelor))
    @c1 = Course.create!(course_no: "9970011", name: "Transcript Course A",
                         revision_year_be: 2566, credits: 3)
    @c2 = Course.create!(course_no: "9970012", name: "Transcript Course B",
                         revision_year_be: 2566, credits: 3)
    @c3 = Course.create!(course_no: "9970013", name: "Transcript Course C",
                         revision_year_be: 2566, credits: 3)

    Grade.create!(student: @student, course: @c1, year_ce: 2056, semester: 1,
                  grade: "A", grade_weight: 4.0, source: "imported")
    Grade.create!(student: @student, course: @c2, year_ce: 2056, semester: 1,
                  grade: "C+", grade_weight: 2.5, source: "imported")
    Grade.create!(student: @student, course: @c3, year_ce: 2056, semester: 2,
                  grade: "B", grade_weight: 3.0, source: "imported")
    # Withdrawn: no weight — must appear in courses but not affect GPA.
    Grade.create!(student: @student, course: @c1, year_ce: 2056, semester: 2,
                  grade: "W", grade_weight: nil, source: "imported")
  end

  test "terms are ascending with per-term GPA and cumulative GPAX" do
    result = GradeStats::StudentTranscript.call(student: @student)
    terms = result[:terms]

    assert_equal 2, terms.size
    assert_equal [ 2056, 1 ], [ terms[0][:year_ce], terms[0][:semester] ]
    assert_equal [ 2056, 2 ], [ terms[1][:year_ce], terms[1][:semester] ]

    # Term 1: (4.0*3 + 2.5*3) / 6 = 3.25
    assert_in_delta 3.25, terms[0][:gpa], 0.001
    assert_in_delta 3.25, terms[0][:gpax], 0.001

    # Term 2: 3.0; GPAX: (12 + 7.5 + 9) / 9 = 3.17
    assert_in_delta 3.0, terms[1][:gpa], 0.001
    assert_in_delta 3.17, terms[1][:gpax], 0.001
  end

  test "non-weighted grades appear as course rows but are excluded from GPA" do
    terms = GradeStats::StudentTranscript.call(student: @student)[:terms]
    term2_grades = terms[1][:courses].map { |c| c[:grade] }

    assert_includes term2_grades, "W"
    assert_equal 2, terms[1][:courses].size
  end

  test "student with no grades returns empty terms" do
    empty = Student.create!(student_id: "9900000802", first_name: "N", last_name: "G",
                            first_name_th: "น", last_name_th: "ก",
                            admission_year_be: 2599, status: "active",
                            program: programs(:cp_bachelor))
    assert_equal [], GradeStats::StudentTranscript.call(student: empty)[:terms]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/grade_stats/student_transcript_test.rb`
Expected: FAIL — `NameError: uninitialized constant GradeStats::StudentTranscript`

- [ ] **Step 3: Implement**

Create `app/services/grade_stats/student_transcript.rb`:

```ruby
module GradeStats
  # Per-term transcript for ONE student: every course row (including
  # non-weighted grades like S/U/W — they are part of the record), the term
  # GPA over weighted grades only, and the cumulative GPAX through each term.
  # Chula transcript naming: GPA = semester, GPAX = cumulative.
  class StudentTranscript
    def self.call(student:)
      rows = student.grades.joins(:course)
                    .order(:year_ce, :semester, "courses.course_no")
                    .pluck(:year_ce, :semester, "courses.course_no", "courses.name",
                           "courses.credits", :grade, :grade_weight)

      cum_points = 0.0
      cum_credits = 0.0

      terms = rows.group_by { |r| r[0, 2] }.map do |(year_ce, semester), term_rows|
        courses = term_rows.map do |_, _, course_no, name, credits, grade, _|
          { course_no: course_no, name: name, credits: credits.to_f, grade: grade }
        end

        weighted = term_rows.reject { |r| r[6].nil? }
        points = weighted.sum { |r| r[6].to_f * r[4].to_f }
        credits = weighted.sum { |r| r[4].to_f }
        cum_points += points
        cum_credits += credits

        {
          year_ce: year_ce, semester: semester, courses: courses,
          gpa: credits.zero? ? nil : (points / credits).round(2),
          gpax: cum_credits.zero? ? nil : (cum_points / cum_credits).round(2)
        }
      end

      { terms: terms }
    end
  end
end
```

(`rows` is ordered by year/semester and `group_by` preserves insertion order, so `terms` comes out ascending without a second sort.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/grade_stats/`
Expected: PASS (new test + existing grade_stats tests untouched).

- [ ] **Step 5: Commit**

```bash
hg add app/services/grade_stats/student_transcript.rb test/services/grade_stats/student_transcript_test.rb
hg commit app/services/grade_stats/student_transcript.rb test/services/grade_stats/student_transcript_test.rb -m "Add GradeStats::StudentTranscript for per-term GPA/GPAX of one student

The LINE bot needs to answer 'how did student X perform, term by term?' —
per-term course+grade rows with semester GPA and cumulative GPAX. That
computation belongs with the other GradeStats services (same rounding, same
GPA/GPAX naming discipline) so web and LINE can never disagree on the math.

Non-weighted grades (S/U/W/...) stay visible as course rows but are
excluded from GPA, matching how transcripts read."
```

---

### Task 9: `student_grades` tool

**Files:**
- Modify: `app/services/line/tools/student_grades_tool.rb` (replace the NotImplementedError body)
- Modify: `config/initializers/line_tools.rb` (register)
- Test: `test/services/line/tools/student_grades_tool_test.rb`

**Interfaces:**
- Consumes: `GradeStats::StudentTranscript.call(student:)` (Task 8), `Student#display_name`, `Student#gpa`, `Student#total_credits`.
- Produces: registered tool `student_grades`. JSON shape:
  `{ student: { student_id:, name:, program:, admission_year_be:, status: }, terms: [ { term: "2567/1", courses: [...], gpa:, gpax: } ], gpax:, total_credits: }`
  or `{ error: ..., matches: [...] }` on ambiguity.

- [ ] **Step 1: Write the failing test**

Create `test/services/line/tools/student_grades_tool_test.rb`:

```ruby
require "test_helper"

class Line::Tools::StudentGradesToolTest < ActiveSupport::TestCase
  test "returns per-term record by student ID with B.E. term labels" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call("query" => "6732100021"))

    assert_equal "6732100021", result["student"]["student_id"]
    assert_equal "CP", result["student"]["program"]

    # Fixture grades for active_student: 2024/1 (A intro + B gened), 2024/2 (B+ senior)
    terms = result["terms"]
    assert_equal [ "2567/1", "2567/2" ], terms.map { |t| t["term"] }
    assert_in_delta 3.5, terms[0]["gpa"], 0.001            # (4.0*3 + 3.0*3) / 6
    assert_equal %w[2103106 2110101], terms[0]["courses"].map { |c| c["course_no"] }.sort
    assert_in_delta 3.5, result["gpax"], 0.001
  end

  test "semester param filters to one term" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call(
      "query" => "6732100021", "semester" => "2567/2"))

    assert_equal [ "2567/2" ], result["terms"].map { |t| t["term"] }
    assert_equal [ "2110499" ], result["terms"][0]["courses"].map { |c| c["course_no"] }
  end

  test "name query matches and full-name query matches" do
    by_partial = JSON.parse(Line::Tools::StudentGradesTool.call("query" => "ธนวัฒน์"))
    by_full = JSON.parse(Line::Tools::StudentGradesTool.call("query" => "ธนวัฒน์ ศรีเจริญ"))

    assert_equal "6732100021", by_partial["student"]["student_id"]
    assert_equal "6732100021", by_full["student"]["student_id"]
  end

  test "ambiguous query returns disambiguation list" do
    # Student IDs starting "6" match several fixture students by prefix... use
    # a shared name instead: create a second student sharing a name fragment.
    Student.create!(student_id: "9900000901", first_name: "Thanawat", last_name: "Other",
                    first_name_th: "ธนวัฒน์", last_name_th: "อื่น",
                    admission_year_be: 2567, status: "active", program: programs(:cp_bachelor))

    result = JSON.parse(Line::Tools::StudentGradesTool.call("query" => "ธนวัฒน์"))

    assert_match(/Multiple students/, result["error"])
    assert_equal 2, result["matches"].size
    assert result["matches"].all? { |m| m["student_id"].present? }
  end

  test "unknown student returns error" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call("query" => "0000000000"))
    assert_match(/No student found/, result["error"])
  end

  test "bad semester format returns error" do
    result = JSON.parse(Line::Tools::StudentGradesTool.call(
      "query" => "6732100021", "semester" => "first term"))
    assert_match(/Could not parse semester/, result["error"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/line/tools/student_grades_tool_test.rb`
Expected: FAIL — `NotImplementedError`

- [ ] **Step 3: Implement**

Replace the `call` body in `app/services/line/tools/student_grades_tool.rb` (keep the class comment and `DEFINITION` from Task 4) with:

```ruby
  MAX_MATCH_CHOICES = 5

  def self.call(arguments, user: nil)
    query = arguments["query"].to_s.strip
    return { error: "query is required" }.to_json if query.blank?

    students = find_students(query)
    return { error: "No student found matching '#{query}'" }.to_json if students.empty?

    if students.size > 1
      return {
        error: "Multiple students match '#{query}'. Ask which one is meant, then retry with the student ID.",
        matches: students.first(MAX_MATCH_CHOICES).map { |s|
          { student_id: s.student_id, name: s.display_name,
            program: s.program.program_group.code, admission_year_be: s.admission_year_be }
        }
      }.to_json
    end

    student = students.first
    terms = GradeStats::StudentTranscript.call(student: student)[:terms]

    if (semester_str = arguments["semester"].to_s.strip.presence)
      year_be, num = parse_term(semester_str)
      return { error: "Could not parse semester '#{semester_str}'. Use 'YEAR/NUMBER', e.g. '2567/2'." }.to_json unless year_be

      terms = terms.select { |t| t[:year_ce] + 543 == year_be && t[:semester] == num }
    end

    {
      student: {
        student_id: student.student_id,
        name: student.display_name,
        program: student.program.program_group.code,
        admission_year_be: student.admission_year_be,
        status: student.status
      },
      terms: terms.map { |t|
        { term: "#{t[:year_ce] + 543}/#{t[:semester]}",
          courses: t[:courses], gpa: t[:gpa], gpax: t[:gpax] }
      },
      gpax: student.gpa,
      total_credits: student.total_credits
    }.to_json
  end

  def self.find_students(query)
    scope = Student.includes(program: :program_group)
    if query.match?(/\A\d+\z/)
      scope.where("student_id LIKE ?", "#{query}%").order(:student_id).to_a
    else
      like = "%#{query}%"
      scope.where(
        "first_name LIKE :q OR last_name LIKE :q OR " \
        "first_name_th LIKE :q OR last_name_th LIKE :q OR " \
        "CONCAT(first_name, ' ', last_name) LIKE :q OR " \
        "CONCAT(first_name_th, ' ', last_name_th) LIKE :q",
        q: like
      ).order(:student_id).to_a
    end
  end
  private_class_method :find_students

  # "2567/2" → [2567, 2]; nil on anything unparseable.
  def self.parse_term(str)
    year, num = str.split("/")
    return nil unless year.to_i.positive? && num.to_i.positive?

    [ year.to_i, num.to_i ]
  end
  private_class_method :parse_term
```

Register in `config/initializers/line_tools.rb` (append inside the `to_prepare` block, after cohort_gpa):

```ruby
  Line::ToolRegistry.register(
    "student_grades",
    definition: Line::Tools::StudentGradesTool::DEFINITION,
    handler: Line::Tools::StudentGradesTool
  )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tools/student_grades_tool_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg add test/services/line/tools/student_grades_tool_test.rb
hg commit app/services/line/tools/student_grades_tool.rb config/initializers/line_tools.rb test/services/line/tools/student_grades_tool_test.rb -m "Implement and register the student_grades LINE tool

'How does this student perform?' was the biggest gap in the LINE bot's
coverage: student_lookup returns only an overall GPA, with no per-term
breakdown, so term-by-term questions were unanswerable. Eval gate for the
round-2 registry passed (docs/llm-eval-results.md).

Backed by GradeStats::StudentTranscript; finds the student by ID prefix or
TH/EN name (with a disambiguation list on multiple matches), optional
'YEAR/NUMBER' term filter, B.E. term labels, GPA/GPAX naming per Chula
transcript convention."
```

---

### Task 10: `course_enrollment` tool

**Files:**
- Modify: `app/services/line/tools/course_enrollment_tool.rb`
- Modify: `config/initializers/line_tools.rb` (register)
- Test: `test/services/line/tools/course_enrollment_tool_test.rb`

**Interfaces:**
- Consumes: `Grade` joins (`courses`, `students → programs → program_groups`), `Grade#section`.
- Produces: registered tool `course_enrollment`. Count mode JSON: `{ course_no:, year_be:, semester:, total:, by_program_cohort: [ { program:, admission_year_be:, count: } ] }`. Membership mode JSON: `{ course_no:, year_be:, semester:, student: { student_id:, name: }, enrolled:, enrollments: [ { term:, section:, grade: } ] }`.

- [ ] **Step 1: Write the failing test**

Create `test/services/line/tools/course_enrollment_tool_test.rb`:

```ruby
require "test_helper"

class Line::Tools::CourseEnrollmentToolTest < ActiveSupport::TestCase
  # Fixture grades for 2110101 (intro_computing): active_student 2024/1,
  # graduated_student 2022/1 — both CP.

  test "counts enrollment for a year with program × cohort breakdown" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      "course_no" => "2110101", "year" => 2567))

    assert_equal 2567, result["year_be"]
    assert_equal 1, result["total"]
    assert_equal [ { "program" => "CP", "admission_year_be" => 2567, "count" => 1 } ],
                 result["by_program_cohort"]
  end

  test "B.E. and C.E. years are equivalent" do
    be = JSON.parse(Line::Tools::CourseEnrollmentTool.call("course_no" => "2110101", "year" => 2567))
    ce = JSON.parse(Line::Tools::CourseEnrollmentTool.call("course_no" => "2110101", "year" => 2024))
    assert_equal be, ce
  end

  test "semester filter narrows the count" do
    with = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      "course_no" => "2110101", "year" => 2567, "semester" => 2))
    assert_equal 0, with["total"]
  end

  test "student_query checks membership with section and grade" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      "course_no" => "2110101", "year" => 2567, "student_query" => "6732100021"))

    assert result["enrolled"]
    assert_equal "6732100021", result["student"]["student_id"]
    enrollment = result["enrollments"].first
    assert_equal "2567/1", enrollment["term"]
    assert_equal "A", enrollment["grade"]
  end

  test "student_query for a student who did not take the course" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call(
      "course_no" => "2110101", "year" => 2567, "student_query" => "6532100071"))

    refute result["enrolled"]
    assert_equal [], result["enrollments"]
  end

  test "missing required params return error" do
    result = JSON.parse(Line::Tools::CourseEnrollmentTool.call("course_no" => "2110101"))
    assert_match(/required/, result["error"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/line/tools/course_enrollment_tool_test.rb`
Expected: FAIL — `NotImplementedError`

- [ ] **Step 3: Implement**

Replace the `call` body in `app/services/line/tools/course_enrollment_tool.rb`:

```ruby
  def self.call(arguments, user: nil)
    course_no = arguments["course_no"].to_s.strip
    year = arguments["year"].to_i
    return { error: "course_no and year are required" }.to_json if course_no.blank? || year.zero?

    year_ce = year < 2400 ? year : year - 543
    semester = arguments["semester"].presence&.to_i

    scope = Grade.joins(:course).where(courses: { course_no: course_no }, year_ce: year_ce)
    scope = scope.where(semester: semester) if semester

    if (student_query = arguments["student_query"].to_s.strip.presence)
      return membership_result(scope, course_no, year_ce, semester, student_query)
    end

    breakdown = scope.joins(student: { program: :program_group })
                     .group("program_groups.code", "students.admission_year_be")
                     .count
                     .map { |(code, admission_year), count|
                       { program: code, admission_year_be: admission_year, count: count } }
                     .sort_by { |row| [ row[:program], row[:admission_year_be] ] }

    {
      course_no: course_no,
      year_be: year_ce + 543,
      semester: semester,
      total: scope.count,
      by_program_cohort: breakdown
    }.to_json
  end

  def self.membership_result(scope, course_no, year_ce, semester, student_query)
    students =
      if student_query.match?(/\A\d+\z/)
        Student.where("student_id LIKE ?", "#{student_query}%")
      else
        like = "%#{student_query}%"
        Student.where("first_name LIKE :q OR last_name LIKE :q OR " \
                      "first_name_th LIKE :q OR last_name_th LIKE :q", q: like)
      end.limit(2).to_a

    return { error: "No student found matching '#{student_query}'" }.to_json if students.empty?
    return { error: "Multiple students match '#{student_query}'. Retry with the exact student ID." }.to_json if students.size > 1

    student = students.first
    rows = scope.where(student_id: student.id).includes(:section).to_a

    {
      course_no: course_no,
      year_be: year_ce + 543,
      semester: semester,
      student: { student_id: student.student_id, name: student.display_name },
      enrolled: rows.any?,
      enrollments: rows.map { |g|
        { term: "#{g.year_ce + 543}/#{g.semester}",
          section: g.section&.section_number,
          grade: g.grade }
      }
    }.to_json
  end
  private_class_method :membership_result
```

Register in `config/initializers/line_tools.rb`:

```ruby
  Line::ToolRegistry.register(
    "course_enrollment",
    definition: Line::Tools::CourseEnrollmentTool::DEFINITION,
    handler: Line::Tools::CourseEnrollmentTool
  )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tools/course_enrollment_tool_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
hg add test/services/line/tools/course_enrollment_tool_test.rb
hg commit app/services/line/tools/course_enrollment_tool.rb config/initializers/line_tools.rb test/services/line/tools/course_enrollment_tool_test.rb -m "Implement and register the course_enrollment LINE tool

'How many students take X, from which programs?' and 'did student S take
X this term?' had no tool: grade_distribution only counts per grade value
and student_lookup knows nothing about courses. Deliberately no bulk
roster output — counts, a program × cohort breakdown, and a single-student
membership check cover the real questions without dumping student lists
into chat.

Same revision-insensitive convention as grade_distribution (Grade rows
matched by course_no), same era rule (year < 2400 = C.E.)."
```

---

### Task 11: `Line::Tools::SemesterParam` helper + `semester_overview` tool

**Files:**
- Create: `app/services/line/tools/semester_param.rb`
- Modify: `app/services/line/tools/semester_overview_tool.rb`
- Modify: `config/initializers/line_tools.rb` (register)
- Test: `test/services/line/tools/semester_overview_tool_test.rb`

**Interfaces:**
- Consumes: `Semester.ordered`, `CourseOffering`, `Section`, `Course → Program → ProgramGroup`.
- Produces:
  - `Line::Tools::SemesterParam.resolve(str) → Semester | { error: String }` — blank str = latest semester; also used by Task 12. Caller pattern: `return semester.to_json unless semester.is_a?(Semester)`.
  - Registered tool `semester_overview`. JSON: `{ semester: "2568/1", offerings:, sections:, distinct_courses:, by_program: [ { program:, offerings: } ] }`.

- [ ] **Step 1: Write the failing test**

Create `test/services/line/tools/semester_overview_tool_test.rb`:

```ruby
require "test_helper"

class Line::Tools::SemesterOverviewToolTest < ActiveSupport::TestCase
  # Fixtures: sem_2568_1 has 2 offerings (2110101 confirmed ×2 sections,
  # 2110499 planned ×1 section); sem_2567_1 has 2 offerings (2110101 ×2
  # sections, 2103106 ×1 section).

  test "explicit semester returns counts and per-program breakdown" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call("semester" => "2568/1"))

    assert_equal "2568/1", result["semester"]
    assert_equal 2, result["offerings"]
    assert_equal 3, result["sections"]
    assert_equal 2, result["distinct_courses"]
    assert result["by_program"].is_a?(Array)
    assert result["by_program"].all? { |row| row["program"].present? && row["offerings"].positive? }
  end

  test "omitted semester defaults to the latest" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call({}))
    assert_equal Semester.ordered.first.display_name, result["semester"]
  end

  test "unknown semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call("semester" => "2500/1"))
    assert_match(/No semester 2500\/1/, result["error"])
  end

  test "unparseable semester returns error" do
    result = JSON.parse(Line::Tools::SemesterOverviewTool.call("semester" => "next term"))
    assert_match(/Could not parse semester/, result["error"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/line/tools/semester_overview_tool_test.rb`
Expected: FAIL — `NotImplementedError`

- [ ] **Step 3: Implement helper + tool**

Create `app/services/line/tools/semester_param.rb`:

```ruby
# Shared resolution of the optional 'YEAR/NUMBER' (B.E.) semester parameter
# used by LINE tools that default to the latest semester. Returns a Semester
# on success, or an { error: } hash the caller returns as JSON:
#
#   semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
#   return semester.to_json unless semester.is_a?(Semester)
#
# (course_offering_lookup keeps its own parser: for it, a blank semester
# means "all semesters", not "the latest".)
module Line::Tools::SemesterParam
  module_function

  def resolve(str)
    str = str.to_s.strip
    if str.blank?
      return Semester.ordered.first || { error: "No semesters in the system yet." }
    end

    year, num = str.split("/")
    unless year.to_i.positive? && num.to_i.positive?
      return { error: "Could not parse semester '#{str}'. Use 'YEAR/NUMBER', e.g. '2568/1'." }
    end

    Semester.find_by(year_be: year.to_i, semester_number: num.to_i) ||
      { error: "No semester #{str} in the system." }
  end
end
```

Replace the `call` body in `app/services/line/tools/semester_overview_tool.rb`:

```ruby
  def self.call(arguments, user: nil)
    semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
    return semester.to_json unless semester.is_a?(Semester)

    offerings = CourseOffering.where(semester: semester)
    sections = Section.joins(:course_offering).where(course_offerings: { semester_id: semester.id })

    by_program = offerings.joins(course: { program: :program_group })
                          .group("program_groups.code")
                          .count
                          .map { |code, count| { program: code, offerings: count } }
                          .sort_by { |row| row[:program] }

    {
      semester: semester.display_name,
      offerings: offerings.count,
      sections: sections.count,
      distinct_courses: offerings.joins(:course).distinct.count("courses.course_no"),
      by_program: by_program
    }.to_json
  end
```

Register in `config/initializers/line_tools.rb`:

```ruby
  Line::ToolRegistry.register(
    "semester_overview",
    definition: Line::Tools::SemesterOverviewTool::DEFINITION,
    handler: Line::Tools::SemesterOverviewTool
  )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tools/semester_overview_tool_test.rb`
Expected: PASS. If the section/offering counts differ, re-check the fixture files (`test/fixtures/course_offerings.yml`, `sections.yml`) and correct the expected numbers to match the fixtures — do not change fixtures.

- [ ] **Step 5: Commit**

```bash
hg add app/services/line/tools/semester_param.rb test/services/line/tools/semester_overview_tool_test.rb
hg commit app/services/line/tools/semester_param.rb app/services/line/tools/semester_overview_tool.rb config/initializers/line_tools.rb test/services/line/tools/semester_overview_tool_test.rb -m "Implement and register the semester_overview LINE tool

'How many courses are offered this term?' had no answer path — 
course_offering_lookup is strictly per-course. One tool call now returns
offering/section/distinct-course counts plus a per-program breakdown,
defaulting to the latest semester.

Extracts the 'YEAR/NUMBER or latest' semester-param resolution into
Line::Tools::SemesterParam, shared with the upcoming room_schedule tool."
```

---

### Task 12: `room_schedule` tool

**Files:**
- Modify: `app/services/line/tools/room_schedule_tool.rb`
- Modify: `config/initializers/line_tools.rb` (register)
- Test: `test/services/line/tools/room_schedule_tool_test.rb`

**Interfaces:**
- Consumes: `Line::Tools::SemesterParam.resolve` (Task 11), `Room` (`display_name`, `building`, `room_number`), `TimeSlot` (`DAY_NAMES`, `day_name`, `time_range`), joins mirroring `SchedulesController#room`.
- Produces: registered tool `room_schedule`. JSON: `{ room: "ENG4-303", semester: "2568/1", capacity:, room_type:, entries: [ { day:, time:, course_no:, name:, section:, instructors: [] } ] }`; disambiguation `{ error:, matches: [names] }`.

- [ ] **Step 1: Write the failing test**

Create `test/services/line/tools/room_schedule_tool_test.rb`:

```ruby
require "test_helper"

class Line::Tools::RoomScheduleToolTest < ActiveSupport::TestCase
  # Fixtures: room eng4_303 hosts intro_sec_1 (2110101, 2568/1) Mon+Wed
  # 09:00-10:30, taught by lecturer_smith.

  test "returns weekly schedule for an exact room name" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      "room" => "ENG4-303", "semester" => "2568/1"))

    assert_equal "ENG4-303", result["room"]
    assert_equal "2568/1", result["semester"]
    assert_equal 2, result["entries"].size

    entry = result["entries"].first
    assert_equal "Monday", entry["day"]
    assert_equal "09:00-10:30", entry["time"]
    assert_equal "2110101", entry["course_no"]
    assert_equal 1, entry["section"]
    assert_includes entry["instructors"], "จอห์น สมิธ"
  end

  test "day filter narrows entries" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      "room" => "ENG4-303", "semester" => "2568/1", "day" => "Mon"))

    assert_equal [ "Monday" ], result["entries"].map { |e| e["day"] }
  end

  test "ambiguous room query returns match list" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call("room" => "ENG4"))

    assert_match(/Multiple rooms/, result["error"])
    assert_includes result["matches"], "ENG4-303"
  end

  test "unknown room returns error" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call("room" => "BLDG9-999"))
    assert_match(/No room found/, result["error"])
  end

  test "unparseable day returns error" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      "room" => "ENG4-303", "day" => "someday"))
    assert_match(/Could not parse day/, result["error"])
  end

  test "room with no classes reports an empty schedule" do
    result = JSON.parse(Line::Tools::RoomScheduleTool.call(
      "room" => "ENG3-201", "semester" => "2568/1"))

    assert_equal [], result["entries"]
    assert_match(/No classes/, result["note"])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/line/tools/room_schedule_tool_test.rb`
Expected: FAIL — `NotImplementedError`

- [ ] **Step 3: Implement**

Replace the `call` body in `app/services/line/tools/room_schedule_tool.rb`:

```ruby
  MAX_MATCH_CHOICES = 10

  def self.call(arguments, user: nil)
    room_query = arguments["room"].to_s.strip
    return { error: "room is required" }.to_json if room_query.blank?

    rooms = Room.where(
      "CONCAT(building, '-', room_number) LIKE :q OR building LIKE :q OR room_number LIKE :q",
      q: "%#{room_query}%"
    ).order(:building, :room_number).to_a

    return { error: "No room found matching '#{room_query}'" }.to_json if rooms.empty?
    if rooms.size > 1
      return {
        error: "Multiple rooms match '#{room_query}'. Retry with the full room name.",
        matches: rooms.first(MAX_MATCH_CHOICES).map(&:display_name)
      }.to_json
    end
    room = rooms.first

    semester = Line::Tools::SemesterParam.resolve(arguments["semester"])
    return semester.to_json unless semester.is_a?(Semester)

    day_index = nil
    if (day_str = arguments["day"].to_s.strip.presence)
      day_index = TimeSlot::DAY_NAMES.index { |name| name.downcase.start_with?(day_str.downcase) }
      return { error: "Could not parse day '#{day_str}'. Use an English day name like 'Tuesday' or 'Tue'." }.to_json unless day_index
    end

    slots = TimeSlot.where(room: room)
                    .joins(section: :course_offering)
                    .where(course_offerings: { semester_id: semester.id })
                    .includes(section: [ { teachings: :staff }, { course_offering: :course } ])
    slots = slots.where(day_of_week: day_index) if day_index

    entries = slots.sort_by { |ts| [ ts.day_of_week, ts.start_time ] }.map do |ts|
      offering = ts.section.course_offering
      {
        day: ts.day_name,
        time: ts.time_range,
        course_no: offering.course.course_no,
        name: offering.course.name,
        section: ts.section.section_number,
        instructors: ts.section.teachings.map { |t| t.staff.display_name_th }
      }
    end

    {
      room: room.display_name,
      semester: semester.display_name,
      capacity: room.capacity,
      room_type: room.room_type,
      entries: entries,
      note: entries.empty? ? "No classes scheduled in this room for #{semester.display_name}." : nil
    }.compact.to_json
  end
```

Register in `config/initializers/line_tools.rb`:

```ruby
  Line::ToolRegistry.register(
    "room_schedule",
    definition: Line::Tools::RoomScheduleTool::DEFINITION,
    handler: Line::Tools::RoomScheduleTool
  )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tools/room_schedule_tool_test.rb`
Expected: PASS. (The "ambiguous" test assumes ≥2 fixture rooms in building ENG4 — `eng4_303` and `eng4_lab1` — check `test/fixtures/rooms.yml` if it fails.)

- [ ] **Step 5: Commit**

```bash
hg add test/services/line/tools/room_schedule_tool_test.rb
hg commit app/services/line/tools/room_schedule_tool.rb config/initializers/line_tools.rb test/services/line/tools/room_schedule_tool_test.rb -m "Implement and register the room_schedule LINE tool

Room-centric schedule questions ('what's in ENG4-303?', 'is it free
Tuesday?') had no tool — course_offering_lookup starts from a course and
the room report only exists as a web page. Mirrors the room report's query
(TimeSlot → Section → CourseOffering scoped to room + semester) as compact
JSON with fuzzy room matching and an optional weekday filter."
```

---

### Task 13: Extend `staff_lookup` with a per-semester teaching summary

**Files:**
- Modify: `app/services/line/tools/staff_lookup_tool.rb`
- Test: `test/services/line/tools/staff_lookup_tool_test.rb` (add tests)

**Interfaces:**
- Consumes: `Staff#teachings` → `Section` → `CourseOffering` → `Course`/`Semester`; `Teaching#load_ratio`.
- Produces: each serialized staff hash gains `teaching: [ { semester: "2568/1", sections: [ "2110101 Sec 1", ... ], section_count:, total_load: } ]` — newest first, max 3 semesters, `[]` for non-teaching staff.

- [ ] **Step 1: Write the failing test**

Add to `test/services/line/tools/staff_lookup_tool_test.rb`:

```ruby
  test "includes per-semester teaching summary with load totals" do
    result = JSON.parse(Line::Tools::StaffLookupTool.call("query" => "JS"))
    teaching = result["staff"].first["teaching"]

    # lecturer_smith fixtures: 2568/1 → intro_sec_1 (1.0) + intro_sec_2 (0.5);
    # 2567/2 → 1 section; 2567/1 → 2 sections.
    assert_equal [ "2568/1", "2567/2", "2567/1" ], teaching.map { |t| t["semester"] }

    latest = teaching.first
    assert_equal 2, latest["section_count"]
    assert_in_delta 1.5, latest["total_load"], 0.001
    assert_includes latest["sections"], "2110101 Sec 1"
  end

  test "staff with no teachings gets an empty teaching list" do
    result = JSON.parse(Line::Tools::StaffLookupTool.call("query" => "Brown"))
    assert_equal [], result["staff"].first["teaching"]
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/line/tools/staff_lookup_tool_test.rb`
Expected: FAIL — `teaching` key is nil.

- [ ] **Step 3: Implement**

In `app/services/line/tools/staff_lookup_tool.rb`:

1. Append to the `description:` string in `DEFINITION` (inside the existing string concatenation):

```ruby
                 "Also returns recent teaching assignments per semester with section counts and total " \
                 "teaching load — use this for 'what does X teach?' and 'how much does X teach?'."
```

2. Add a constant under `DEFAULT_LIMIT`:

```ruby
  RECENT_TERMS = 3
```

3. In `serialize`, add the key:

```ruby
      programs: staff_member.programs.includes(:program_group).map { |p|
        "#{p.program_group.code} (#{p.year_started_be})"
      },
      teaching: teaching_summary(staff_member)
```

4. Add the private method:

```ruby
  # Last few semesters of teaching — what, how many sections, and the summed
  # load_ratio — so "how much does X teach?" needs no second tool. Newest
  # first, capped at RECENT_TERMS semesters.
  def self.teaching_summary(staff_member)
    teachings = staff_member.teachings
                            .includes(section: { course_offering: [ :course, :semester ] })
                            .to_a
    return [] if teachings.empty?

    by_semester = teachings.group_by { |t| t.section.course_offering.semester }
    by_semester.keys.sort_by { |s| [ -s.year_be, -s.semester_number ] }.first(RECENT_TERMS).map do |sem|
      sem_teachings = by_semester[sem]
      {
        semester: sem.display_name,
        sections: sem_teachings.map { |t|
          offering = t.section.course_offering
          "#{offering.course.course_no} Sec #{t.section.section_number}"
        }.sort,
        section_count: sem_teachings.size,
        total_load: sem_teachings.sum { |t| t.load_ratio.to_f }.round(2)
      }
    end
  end
  private_class_method :teaching_summary
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/line/tools/staff_lookup_tool_test.rb`
Expected: PASS (new + existing tests).

- [ ] **Step 5: Commit**

```bash
hg commit app/services/line/tools/staff_lookup_tool.rb test/services/line/tools/staff_lookup_tool_test.rb -m "Add per-semester teaching summary to the staff_lookup LINE tool

'What does X teach?' and 'how much load does X carry?' are among the most
common staff questions, but staff_lookup returned only profile fields —
and a separate staff_workload tool would be a description twin that
degrades tool selection (the round-2 design explicitly consolidates here
instead). Each result now carries the last 3 semesters of teaching with
sections, counts, and summed load_ratio."
```

---

### Task 14: Docs, backlog trigger, final verification

**Files:**
- Modify: `docs/line-integration.md` (tool inventory + eval workflow)
- Modify: `docs/backlog.md` (new triggered item)

**Interfaces:** none (docs).

- [ ] **Step 1: Rewrite the tool inventory in `docs/line-integration.md`**

Replace the `### Tool inventory` table (including the two `*(planned)*` rows — `schedule_lookup` is superseded by `room_schedule` + `course_offering_lookup`; `grade_summary` by `grade_distribution` + `cohort_gpa`) with:

```markdown
### Tool inventory

| Tool | Purpose | Example queries |
|---|---|---|
| `student_lookup` | Find students by ID/name/program/year/status. Profile, GPA, credits, counts. | "ขอข้อมูล 6530200321", "how many 2nd year CP students?" |
| `student_grades` | One student's record term by term: courses+grades, GPA, GPAX. | "ผลการเรียนของ 6530200321", "is X improving?" |
| `staff_lookup` | Find staff by name/initials; includes recent per-semester teaching summary with load totals. | "what does อ.ณัฐ teach?", "ภาระงานสอนของ อ.สมชาย" |
| `course_lookup` | Static course info by course_no or name (TH/EN): credits, revision, program. | "วิชา 2110327 กี่หน่วยกิต" |
| `course_offering_lookup` | Who teaches a course, its sections and meeting times, per semester. | "who teaches 2110211?", "2110327 มีกี่เซค" |
| `course_enrollment` | Enrollment counts for a course-term (program × cohort breakdown) + single-student membership check. | "how many students take 2110101?", "did 6530200321 enroll in 2110499?" |
| `grade_distribution` | Count per grade + course GPA for a course-term. | "grade distribution for 2110327" |
| `cohort_gpa` | Per-semester GPA/GPAX statistics for one admission cohort. | "average GPA of CP 65" |
| `semester_overview` | Offerings/sections/courses counts for a term, by program. | "how many courses offered in 2568/1?" |
| `room_schedule` | A room's weekly class schedule for a term. | "what's in ENG4-303?", "ห้อง 303 วันอังคาร" |
| `search` | Cross-entity search when the query is ambiguous. | "สมชาย" |

### Tool-selection eval

`bin/rails llm:eval` scores tool selection against `test/llm_eval/cases.yml`
(selection-only — tools never execute). Knobs: `MODEL=` (llm.yml key), `N=`
repeats, `CASES=` id filter, `REGISTRY=current|candidate`, `SWEEP=1` for the
accuracy-vs-registry-size curve with decoy tools. Results history:
`docs/llm-eval-results.md`. **Every tool addition or description change must
add/adjust cases and re-run the eval** (gate: no more than a 3-point drop on
existing cases for qwen, ≥80% on new cases). Standard matrix: qwen + gemma
(always live); glm/kimi opportunistically when swapped into the DGX slot.
```

- [ ] **Step 2: Add the backlog trigger item**

Append to `docs/backlog.md` before the "How to add an item" section:

```markdown
## 4. LINE tool coverage (recurring)

**Trigger: any new/changed report, any new/changed entity show page, any new
data domain (a new model with user-facing value).**

When the web app learns to answer a new question, decide whether the LINE bot
should answer it too. Check the tool inventory in `docs/line-integration.md`:

- **If yes**: extend an existing entity-focused tool before adding a new one —
  overlapping "twin" tools measurably degrade model tool selection (see
  `docs/llm-data-query.md`). Add eval cases to `test/llm_eval/cases.yml`
  covering the new capability (Thai + English), then run
  `bin/rails llm:eval MODEL=qwen` and compare against
  `docs/llm-eval-results.md` (gate: ≤3-point drop on existing cases, ≥80% on
  new cases). Record the numbers there.
- **If no**: note why below, so the next session doesn't re-litigate.

Decisions so far (2026-07-21): schedule *conflict* reports and the teaching
matrix stay web-only (dense cross-tabs, unreadable in chat); data-coverage is
admin tooling, not chat material.
```

- [ ] **Step 3: Full verification**

Run: `bin/rails test`
Expected: full unit/model suite PASS (system tests not run — pre-existing teaching-matrix system test breakage is out of scope).

Run: `bin/rails runner "puts Line::ToolRegistry.definitions.size"`
Expected: `11`

Run: `bin/rails llm:eval MODEL=qwen N=1 CASES=transcript_all_terms,enrollment_count_en,overview_named_term,room_week`
Expected: 4 PASS lines (the registry now includes the four new tools; `REGISTRY=current` == candidate).

- [ ] **Step 4: Commit**

```bash
hg commit docs/line-integration.md docs/backlog.md -m "Document round-2 LINE tools and add the tool-coverage backlog trigger

The tool inventory in line-integration.md was already stale before this
round (missing three shipped tools), which is exactly how coverage
questions go unanswered: nothing forces the 'should LINE answer this too?'
decision when the web app grows. The new backlog item makes that decision
explicit at every report/entity-page change, and ties it to the llm:eval
gate so additions are measured, not hoped.

Inventory rewritten with all 11 tools (planned rows superseded); eval
workflow documented."
```

---

## Self-Review Notes

- **Spec coverage**: eval harness + sweep (Tasks 5–7), user plumbing (2), echo retirement (3), four tools (4, 9–12), staff_lookup extension (13), backlog + inventory (14), gate criteria (7). Personal my-schedule queries, per-tool authorization rules, commercial models: out of scope per spec.
- **Fixture-dependent assertions** (Tasks 9–13 tests) cite the fixture rows they rely on; if counts mismatch, fix the *expected values* after re-reading fixtures — never edit fixtures for these tests.
- **Type consistency**: handler signature `call(arguments, user: nil)` set in Task 2, used by Tasks 4, 9–13; `SemesterParam.resolve` defined in Task 11, consumed in Task 12; Runner result keys match rake CSV columns.
