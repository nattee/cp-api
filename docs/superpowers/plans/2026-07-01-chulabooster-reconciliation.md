# ChulaBooster Reconciliation (Dry-Run) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only rake task that diffs all five ChulaBooster export entities against the local DB and reports, per entity, which records are identical / changed / CB-only / local-only.

**Architecture:** A reusable read-only `Chulabooster::Client` (keyset pagination) feeds a `Chulabooster::Reconciler` that matches CB rows to local records via per-entity mappers (applying the crosswalks), streaming results through a `Chulabooster::ReportWriter` to console + files. A `chulabooster:reconcile` rake task orchestrates all five entities with page-level resume.

**Tech Stack:** Ruby 3.4.8, Rails 8.1, MySQL 8, Minitest + fixtures, Net::HTTP, Mercurial (hg).

**Spec:** `docs/superpowers/specs/2026-07-01-chulabooster-reconciliation-design.md`

## Global Constraints

- **VCS is Mercurial (hg), NOT git.** Commit with `hg commit <explicit paths> -m "..."`; always name explicit files; first line of every message leads with WHY.
- **Read-only:** no `save`/`create`/`update`/`destroy`/`insert`/`delete` anywhere in this feature's code path. The client only issues HTTP `GET` to `/api/ext/export/*`.
- **Years are Buddhist Era (B.E.)** locally; CB years are C.E. — convert with `+543` when the value is `< 2400`.
- **Confirmed crosswalks:** CB `program_id` ↔ local `program_code`; CB `program_code` ↔ local `alternative_program_code`; `*_alt` = Thai, base = English; CB `course_id` = 4-digit CE year + `course_no`.
- **Encoding-unverified fields** (`student_status`, `semester_code`, `grade_type`): compare/normalize best-effort and flag `verified: false` in the report — do not fabricate an authoritative mapping.
- **No HTTP mock gem** — tests stub by overriding a seam method with `define_singleton_method` (house style; see `test/services/scrapers/cu_get_reg_test.rb`).
- Credentials: `Rails.application.credentials.chulabooster` → `base_url`, `app_id`, `app_secret`.
- Run tests with `bin/rails test`.

## File Structure

| Path | Responsibility |
|---|---|
| `app/services/chulabooster/client.rb` | read-only paginating HTTP client + error classes |
| `app/services/chulabooster/convert.rb` | shared value coercions (CE→BE, bool, string/int normalize) |
| `app/services/chulabooster/mappers/base.rb` | mapper interface + shared diff helper |
| `app/services/chulabooster/mappers/{programs,courses,students,program_courses,student_courses}.rb` | per-entity key + field mapping |
| `app/services/chulabooster/reconciler.rb` | per-entity streaming diff engine + checkpoint |
| `app/services/chulabooster/report_writer.rb` | append CSVs, write summary.md, build console table |
| `lib/tasks/chulabooster.rake` | `reconcile` orchestrator (all 5 entities, fresh + RESUME) |
| `test/services/chulabooster/*_test.rb` | tests per component |

---

### Task 1: `Chulabooster::Client` (read-only paginating API client)

**Files:**
- Create: `app/services/chulabooster/client.rb`
- Test: `test/services/chulabooster/client_test.rb`

**Interfaces:**
- Produces: `Chulabooster::Client.new(config:)`; `#each_page(entity, changed_since:, start_cursor:) { |rows, next_cursor| }`; `#each_row(entity, **opts) { |row| }`; error classes `Chulabooster::AuthError`, `PermissionError`, `RequestError`. Seam: private `#perform(request, uri) -> [Integer, String]` (tests override).

- [ ] **Step 1: Write the client**

Create `app/services/chulabooster/client.rb`:

```ruby
require "net/http"
require "json"

module Chulabooster
  class Error < StandardError; end
  class AuthError < Error; end        # 401
  class PermissionError < Error; end  # 403
  class RequestError < Error; end     # other 4xx / exhausted retries

  class Client
    EXPORT_ENTITIES = %w[programs courses students student_courses program_courses].freeze
    BASE_PATH    = "/api/ext/export"
    PAGE_SIZE    = 500
    RETRY_COUNT  = 3
    RETRY_DELAY  = 2
    OPEN_TIMEOUT = 8
    READ_TIMEOUT = 180  # student_courses is ~26s/request

    def initialize(config: Rails.application.credentials.chulabooster)
      @base_url   = config.fetch(:base_url)
      @app_id     = config.fetch(:app_id)
      @app_secret = config.fetch(:app_secret)
    end

    def each_page(entity, changed_since: nil, start_cursor: nil)
      validate!(entity)
      cursor = start_cursor
      loop do
        page = fetch_page(entity, cursor: cursor, changed_since: changed_since)
        yield page.fetch(entity), page["next_cursor"]
        cursor = page["next_cursor"]
        break if cursor.nil?
      end
    end

    def each_row(entity, **opts)
      each_page(entity, **opts) { |rows, _cursor| rows.each { |r| yield r } }
    end

    private

    def validate!(entity)
      EXPORT_ENTITIES.include?(entity) or raise ArgumentError, "unknown entity #{entity.inspect}"
    end

    def fetch_page(entity, cursor:, changed_since:)
      params = { limit: PAGE_SIZE }
      params[:cursor] = cursor if cursor
      params[:changed_since] = changed_since if changed_since
      uri = URI("#{@base_url}#{BASE_PATH}/#{entity}")
      uri.query = URI.encode_www_form(params)

      req = Net::HTTP::Get.new(uri)
      req["DeeAppId"] = @app_id
      req["DeeAppSecret"] = @app_secret

      attempt = 0
      begin
        attempt += 1
        code, body = perform(req, uri)
        case code
        when 200 then return JSON.parse(body)
        when 401 then raise AuthError, "ChulaBooster 401 (bad credentials)"
        when 403 then raise PermissionError, "ChulaBooster 403: #{body.to_s[0, 200]}"
        when 400..499 then raise RequestError, "ChulaBooster #{code}: #{body.to_s[0, 200]}"
        else raise RequestError, "ChulaBooster #{code}"
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, RequestError => e
        raise if e.is_a?(RequestError) && attempt > RETRY_COUNT
        if attempt <= RETRY_COUNT
          sleep(RETRY_DELAY)
          retry
        end
        raise RequestError, "ChulaBooster #{entity} failed after #{attempt} attempts: #{e.message}"
      end
    end

    # Seam for tests (override via define_singleton_method). Real impl does the HTTP GET.
    def perform(request, uri)
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
      [res.code.to_i, res.body.to_s]
    end
  end
end
```

- [ ] **Step 2: Write the tests**

Create `test/services/chulabooster/client_test.rb`:

```ruby
require "test_helper"

class Chulabooster::ClientTest < ActiveSupport::TestCase
  def build_client
    Chulabooster::Client.new(config: { base_url: "https://cb.test", app_id: "id", app_secret: "sec" })
  end

  # Stub the HTTP seam to return a queue of [code, body] responses, recording each request.
  def stub_perform(client, responses)
    reqs = []
    client.define_singleton_method(:perform) do |request, _uri|
      reqs << request
      responses.shift
    end
    reqs
  end

  test "each_page follows next_cursor across pages and stops at null" do
    client = build_client
    stub_perform(client, [
      [200, { "count" => 2, "courses" => [{ "course_no" => "1" }, { "course_no" => "2" }], "next_cursor" => "abc" }.to_json],
      [200, { "count" => 1, "courses" => [{ "course_no" => "3" }], "next_cursor" => nil }.to_json]
    ])
    seen = []
    client.each_page("courses") { |rows, cursor| seen << [rows.map { |r| r["course_no"] }, cursor] }
    assert_equal [[["1", "2"], "abc"], [["3"], nil]], seen
  end

  test "each_row flattens rows across pages" do
    client = build_client
    stub_perform(client, [
      [200, { "count" => 1, "students" => [{ "student_id" => "a" }], "next_cursor" => "c" }.to_json],
      [200, { "count" => 1, "students" => [{ "student_id" => "b" }], "next_cursor" => nil }.to_json]
    ])
    ids = []
    client.each_row("students") { |r| ids << r["student_id"] }
    assert_equal %w[a b], ids
  end

  test "only issues GET requests (read-only)" do
    client = build_client
    reqs = stub_perform(client, [[200, { "count" => 0, "programs" => [], "next_cursor" => nil }.to_json]])
    client.each_page("programs") { |_, _| }
    assert_equal ["GET"], reqs.map(&:method)
  end

  test "unknown entity raises ArgumentError" do
    assert_raises(ArgumentError) { build_client.each_page("teachers") { |_, _| } }
  end

  test "403 raises PermissionError without retry" do
    client = build_client
    reqs = stub_perform(client, [[403, "permission_denied"]])
    assert_raises(Chulabooster::PermissionError) { client.each_page("students") { |_, _| } }
    assert_equal 1, reqs.length
  end

  test "401 raises AuthError" do
    client = build_client
    stub_perform(client, [[401, "unauthorized"]])
    assert_raises(Chulabooster::AuthError) { client.each_page("students") { |_, _| } }
  end

  test "retries on timeout then succeeds" do
    client = build_client
    calls = 0
    client.define_singleton_method(:perform) do |_request, _uri|
      calls += 1
      raise Timeout::Error if calls < 3
      [200, { "count" => 0, "courses" => [], "next_cursor" => nil }.to_json]
    end
    client.stub(:sleep, nil) { client.each_page("courses") { |_, _| } } if client.respond_to?(:stub)
    # Minitest core has no #stub on arbitrary objects here; override sleep on the instance instead:
    client.define_singleton_method(:sleep) { |_n| nil }
    calls = 0
    client.each_page("courses") { |_, _| }
    assert_equal 3, calls
  end
end
```

Note: the retry test overrides `sleep` on the instance to keep it fast; the first `stub` line is a no-op guard and can be removed if `#stub` is unavailable.

- [ ] **Step 3: Run the tests**

Run: `bin/rails test test/services/chulabooster/client_test.rb`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
hg add app/services/chulabooster/client.rb test/services/chulabooster/client_test.rb
hg commit app/services/chulabooster/client.rb test/services/chulabooster/client_test.rb \
  -m "Read ChulaBooster exports safely for the reconciliation dry-run: add a GET-only, keyset-paginating client with retry and typed auth/permission errors"
```

---

### Task 2: `Convert` helper + mapper base + programs/courses/students mappers

**Files:**
- Create: `app/services/chulabooster/convert.rb`, `app/services/chulabooster/mappers/base.rb`, `.../mappers/programs.rb`, `.../mappers/courses.rb`, `.../mappers/students.rb`
- Test: `test/services/chulabooster/mappers_test.rb`

**Interfaces:**
- Produces: `Chulabooster::Convert.ce_to_be(v) -> Integer|nil`, `.bool(v) -> bool`, `.norm(v) -> String` (trimmed downcased string, `""` for nil). Mapper instances respond to `#entity -> String`, `#local_scope -> Enumerable`, `#local_key(rec) -> Object`, `#cb_key(row) -> Object`, `#field_diffs(rec, row) -> Array<Hash{field,local,cb,verified}>`, `#identifiers(row) -> Hash` (CB-only display columns).

- [ ] **Step 1: Write the `Convert` helper**

Create `app/services/chulabooster/convert.rb`:

```ruby
module Chulabooster
  module Convert
    module_function

    # CE→BE per the importer convention (+543 when the value looks like CE).
    def ce_to_be(value)
      return nil if value.nil? || value.to_s.strip.empty?
      n = value.to_i
      n < 2400 ? n + 543 : n
    end

    def bool(value)
      case value
      when true, 1, 1.0, "1", "true", "yes" then true
      else false
      end
    end

    # Normalize a scalar for comparison: trimmed, downcased string; nil/"" both -> "".
    def norm(value)
      value.to_s.strip.downcase
    end

    def int_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      value.to_i
    end
  end
end
```

- [ ] **Step 2: Write the mapper base**

Create `app/services/chulabooster/mappers/base.rb`:

```ruby
module Chulabooster
  module Mappers
    class Base
      # Subclasses implement: entity, local_scope, local_key, cb_key, comparisons, identifiers.

      def field_diffs(local_rec, cb_row)
        comparisons(local_rec, cb_row).filter_map do |field, local_val, cb_val, verified|
          next if Convert.norm(local_val) == Convert.norm(cb_val)
          { field: field.to_s, local: local_val, cb: cb_val, verified: verified }
        end
      end

      # Default: no extra display columns for CB-only rows beyond the key.
      def identifiers(_cb_row) = {}
    end
  end
end
```

- [ ] **Step 3: Write the programs mapper**

Create `app/services/chulabooster/mappers/programs.rb`:

```ruby
module Chulabooster
  module Mappers
    class Programs < Base
      def entity = "programs"
      def local_scope = Program.includes(:program_group)
      def local_key(p) = p.program_code
      def cb_key(row) = row["program_id"].to_s

      def comparisons(p, row)
        [
          [:name_en, p.name_en, row["program_name"], true],
          [:name_th, p.name_th, row["program_name_alt"], true],
          [:year_started, p.year_started, Convert.ce_to_be(row["revision_year"]), true],
          [:alternative_program_code, p.alternative_program_code, row["program_code"], true]
        ]
      end

      def identifiers(row) = { program_name: row["program_name"], revision_year: row["revision_year"] }
    end
  end
end
```

- [ ] **Step 4: Write the courses mapper**

Create `app/services/chulabooster/mappers/courses.rb`:

```ruby
module Chulabooster
  module Mappers
    class Courses < Base
      def entity = "courses"
      def local_scope = Course.all
      def local_key(c) = [c.course_no.to_s, c.revision_year]
      def cb_key(row) = [row["course_no"].to_s, Convert.ce_to_be(row["revision_year"])]

      def comparisons(c, row)
        [
          [:name,      c.name,      row["course_name"],     true],
          [:name_th,   c.name_th,   row["course_name_alt"], true],
          [:credits,   c.credits,   Convert.int_or_nil(row["credits"]),   true],
          [:l_credits, c.l_credits, Convert.int_or_nil(row["l_credits"]), true],
          [:l_hours,   c.l_hours,   Convert.int_or_nil(row["l_hours"]),   true],
          [:nl_hours,  c.nl_hours,  Convert.int_or_nil(row["nl_hours"]),  true],
          [:s_hours,   c.s_hours,   Convert.int_or_nil(row["s_hours"]),   true],
          [:is_thesis, c.is_thesis, Convert.bool(row["is_thesis"]), true],
          [:is_gened,  c.is_gened,  Convert.bool(row["gened"]),     true]
        ]
      end

      def identifiers(row) = { course_name: row["course_name"] }
    end
  end
end
```

- [ ] **Step 5: Write the students mapper**

Create `app/services/chulabooster/mappers/students.rb`:

```ruby
module Chulabooster
  module Mappers
    class Students < Base
      def entity = "students"
      def local_scope = Student.all
      def local_key(s) = s.student_id.to_s
      def cb_key(row) = row["student_id"].to_s

      def comparisons(s, row)
        [
          [:first_name,       s.first_name,       row["firstname"],      true],
          [:last_name,        s.last_name,        row["lastname"],       true],
          [:first_name_th,    s.first_name_th,    row["firstname_alt"],  true],
          [:last_name_th,     s.last_name_th,     row["lastname_alt"],   true],
          [:sex,              s.sex,              row["gender"],         true],
          [:admission_year_be, s.admission_year_be, Convert.ce_to_be(row["start_academic_year"]), true],
          [:status,           s.status,           row["student_status"], false]  # encoding-unverified
        ]
      end

      def identifiers(row) = { firstname: row["firstname"], lastname: row["lastname"] }
    end
  end
end
```

- [ ] **Step 6: Write the tests**

Create `test/services/chulabooster/mappers_test.rb`:

```ruby
require "test_helper"

class Chulabooster::MappersTest < ActiveSupport::TestCase
  test "ce_to_be converts CE and leaves BE" do
    assert_equal 2557, Chulabooster::Convert.ce_to_be(2014)
    assert_equal 2565, Chulabooster::Convert.ce_to_be(2565)
    assert_nil Chulabooster::Convert.ce_to_be(nil)
  end

  test "programs mapper keys and diffs" do
    m = Chulabooster::Mappers::Programs.new
    p = programs(:cp_bachelor)   # program_code "2101"
    assert_equal "2101", m.local_key(p)
    assert_equal "2101", m.cb_key({ "program_id" => "2101" })

    identical = { "program_id" => "2101", "program_name" => p.name_en, "program_name_alt" => p.name_th,
                  "revision_year" => p.year_started - 543, "program_code" => p.alternative_program_code }
    assert_empty m.field_diffs(p, identical)

    changed = identical.merge("program_name" => "Different Name")
    diffs = m.field_diffs(p, changed)
    assert_equal ["name_en"], diffs.map { |d| d[:field] }
  end

  test "courses mapper key uses CE->BE revision and detects a changed field" do
    m = Chulabooster::Mappers::Courses.new
    c = courses(:intro_computing)  # course_no "2110101", revision_year 2565
    assert_equal ["2110101", 2565], m.local_key(c)
    assert_equal ["2110101", 2565], m.cb_key({ "course_no" => "2110101", "revision_year" => 2022 }) # 2022+543
    row = { "course_name" => c.name, "course_name_alt" => c.name_th, "credits" => 99 }
    assert_equal ["credits"], m.field_diffs(c, row).map { |d| d[:field] }
  end

  test "students mapper flags status as encoding-unverified" do
    m = Chulabooster::Mappers::Students.new
    s = students(:active_student)
    row = { "student_id" => s.student_id, "firstname" => s.first_name, "lastname" => s.last_name,
            "firstname_alt" => s.first_name_th, "lastname_alt" => s.last_name_th, "gender" => s.sex,
            "start_academic_year" => s.admission_year_be - 543, "student_status" => "9" }
    diffs = m.field_diffs(s, row)
    status = diffs.find { |d| d[:field] == "status" }
    assert status && status[:verified] == false
  end
end
```

- [ ] **Step 7: Run the tests**

Run: `bin/rails test test/services/chulabooster/mappers_test.rb`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
hg add app/services/chulabooster/convert.rb app/services/chulabooster/mappers/base.rb \
  app/services/chulabooster/mappers/programs.rb app/services/chulabooster/mappers/courses.rb \
  app/services/chulabooster/mappers/students.rb test/services/chulabooster/mappers_test.rb
hg commit app/services/chulabooster/convert.rb app/services/chulabooster/mappers \
  test/services/chulabooster/mappers_test.rb \
  -m "Map ChulaBooster programs/courses/students to local records for the dry-run: shared CE→BE/bool/normalize helpers, a mapper base, and the three direct-key mappers with field comparisons"
```

---

### Task 3: program_courses + student_courses mappers (composite keys, course_id resolution)

**Files:**
- Create: `app/services/chulabooster/mappers/program_courses.rb`, `.../mappers/student_courses.rb`
- Test: `test/services/chulabooster/composite_mappers_test.rb`

**Interfaces:**
- Consumes: `Convert`, `Mappers::Base` (Task 2).
- Produces: `Mappers::ProgramCourses`, `Mappers::StudentCourses`. Both parse CB `course_id` (4-digit CE year + `course_no`) via a shared helper `Convert.parse_course_id(course_id) -> [course_no, revision_year_be]`.

- [ ] **Step 1: Add `parse_course_id` to `Convert`**

In `app/services/chulabooster/convert.rb`, add inside `module Convert` (after `int_or_nil`):

```ruby
    # CB course_id is "<4-digit CE year><course_no>", e.g. "20142110254" -> ["2110254", 2557].
    def parse_course_id(course_id)
      s = course_id.to_s
      [s[4..].to_s, ce_to_be(s[0, 4])]
    end
```

- [ ] **Step 2: Write the program_courses mapper**

Create `app/services/chulabooster/mappers/program_courses.rb`:

```ruby
module Chulabooster
  module Mappers
    class ProgramCourses < Base
      def entity = "program_courses"

      def local_scope = ProgramCourse.includes(:program, :course)

      def local_key(pc)
        [pc.program.program_code.to_s, pc.course.course_no.to_s, pc.course.revision_year]
      end

      def cb_key(row)
        course_no, rev_be = Convert.parse_course_id(row["course_id"])
        course_no = row["course_no"].to_s if row["course_no"].present?
        [row["program_id"].to_s, course_no, rev_be]
      end

      # Membership-only: a matched pair has no comparable managed fields locally.
      def comparisons(_pc, _row) = []

      def identifiers(row) = { course_no: row["course_no"], course_group_code: row["course_group_code"] }
    end
  end
end
```

- [ ] **Step 3: Write the student_courses mapper**

Create `app/services/chulabooster/mappers/student_courses.rb`:

```ruby
module Chulabooster
  module Mappers
    class StudentCourses < Base
      def entity = "student_courses"

      def local_scope = Grade.includes(:student, :course)

      # NOTE: refinement of the spec's listed key — `section` is dropped. The local grade unique index
      # is (student_id, course_id, year, semester); section is not part of local grade identity and most
      # imported grades have a nil section, so including it would cause spurious mismatches.
      def local_key(g)
        [
          g.student.student_id.to_s,
          g.course.course_no.to_s,
          g.course.revision_year,
          g.year,
          Convert.norm(g.semester)
        ]
      end

      def cb_key(row)
        course_no, rev_be = Convert.parse_course_id(row["course_id"])
        [
          row["student_id"].to_s,
          course_no,
          rev_be,
          Convert.ce_to_be(row["academic_year"]),
          Convert.norm(row["semester_code"])  # encoding-unverified key part
        ]
      end

      def comparisons(g, row)
        [
          [:grade,         g.grade,         row["grade"],         true],
          [:credits_grant, g.credits_grant, Convert.int_or_nil(row["credits_grant"]), true]
        ]
      end

      def identifiers(row) = { course_id: row["course_id"], academic_year: row["academic_year"] }
    end
  end
end
```

- [ ] **Step 4: Write the tests**

Create `test/services/chulabooster/composite_mappers_test.rb`:

```ruby
require "test_helper"

class Chulabooster::CompositeMappersTest < ActiveSupport::TestCase
  test "parse_course_id splits CE year and course_no with CE->BE" do
    assert_equal ["2110254", 2557], Chulabooster::Convert.parse_course_id("20142110254")
  end

  test "program_courses mapper matches on (program_code, course_no, revision_be)" do
    m = Chulabooster::Mappers::ProgramCourses.new
    pc = ProgramCourse.joins(:program, :course).first
    key = m.local_key(pc)
    assert_equal 3, key.length
    row = { "program_id" => key[0], "course_no" => key[1],
            "course_id" => "#{key[2] - 543}#{key[1]}" }
    assert_equal key, m.cb_key(row)
    assert_empty m.field_diffs(pc, row)  # membership-only: matched == identical
  end

  test "student_courses mapper builds a 5-part key and compares grade" do
    m = Chulabooster::Mappers::StudentCourses.new
    g = Grade.includes(:student, :course).where.not(grade: [nil, ""]).first
    key = m.local_key(g)
    assert_equal 5, key.length
    row = { "student_id" => key[0], "course_id" => "#{key[2] - 543}#{key[1]}",
            "academic_year" => key[3] - 543, "semester_code" => g.semester.to_s,
            "grade" => "Z", "credits_grant" => g.credits_grant }
    assert_equal key, m.cb_key(row)
    assert_equal ["grade"], m.field_diffs(g, row).map { |d| d[:field] }
  end
end
```

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/services/chulabooster/composite_mappers_test.rb`
Expected: all pass. (If `ProgramCourse`/`Grade` have no rows in the test DB, these use fixtures — confirm `program_courses.yml` and `grades.yml` fixtures exist; they do.)

- [ ] **Step 6: Commit**

```bash
hg add app/services/chulabooster/mappers/program_courses.rb \
  app/services/chulabooster/mappers/student_courses.rb \
  test/services/chulabooster/composite_mappers_test.rb
hg commit app/services/chulabooster/convert.rb \
  app/services/chulabooster/mappers/program_courses.rb \
  app/services/chulabooster/mappers/student_courses.rb \
  test/services/chulabooster/composite_mappers_test.rb \
  -m "Match curriculum and grade rows in the dry-run: composite-key mappers that resolve CB course_id to (course_no, revision B.E.) for program_courses and student_courses"
```

---

### Task 4: `Reconciler` (streaming diff engine) + `ReportWriter`

**Files:**
- Create: `app/services/chulabooster/report_writer.rb`, `app/services/chulabooster/reconciler.rb`
- Test: `test/services/chulabooster/reconciler_test.rb`

**Interfaces:**
- Consumes: `Client` (Task 1), any mapper (Tasks 2–3).
- Produces:
  - `ReportWriter.new(run_dir)` with `#append_changed(entity, rows)`, `#append_cb_only(entity, rows)`, `#append_local_only(entity, keys)`, `#write_summary(counts) -> String` (returns console table), `#seen_path(entity)`.
  - `Reconciler.new(client:, writer:, run_dir:)`; `#reconcile_entity(mapper, start_cursor: nil) -> Hash` (counts: `{entity, local, cb, matched, identical, changed, cb_only, local_only}`), writing rows via the writer and a `checkpoint.json` after each page.

- [ ] **Step 1: Write the ReportWriter**

Create `app/services/chulabooster/report_writer.rb`:

```ruby
require "csv"

module Chulabooster
  class ReportWriter
    def initialize(run_dir)
      @run_dir = run_dir
      FileUtils.mkdir_p(@run_dir)
    end

    def seen_path(entity) = File.join(@run_dir, "#{entity}_seen.tsv")

    def append_changed(entity, rows)  # rows: [{ key:, diffs: [{field,local,cb,verified}] }]
      append_csv("#{entity}_changed.csv", %w[key field local cb verified]) do |csv|
        rows.each do |r|
          r[:diffs].each { |d| csv << [r[:key].inspect, d[:field], d[:local], d[:cb], d[:verified]] }
        end
      end
    end

    def append_cb_only(entity, rows)  # rows: [{ key:, identifiers: {} }]
      cols = %w[key] + (rows.first&.dig(:identifiers)&.keys&.map(&:to_s) || [])
      append_csv("#{entity}_cb_only.csv", cols) do |csv|
        rows.each { |r| csv << [r[:key].inspect, *r[:identifiers].values] }
      end
    end

    def append_local_only(entity, keys)
      append_csv("#{entity}_local_only.csv", %w[key]) { |csv| keys.each { |k| csv << [k.inspect] } }
    end

    def write_summary(counts)  # counts: array of the per-entity hashes
      table = summary_table(counts)
      File.write(File.join(@run_dir, "summary.md"),
                 "# ChulaBooster reconciliation\n\n```\n#{table}\n```\n\nReport dir: #{@run_dir}\n")
      table
    end

    private

    def append_csv(name, header)
      path = File.join(@run_dir, name)
      write_header = !File.exist?(path)
      CSV.open(path, "a") do |csv|
        csv << header if write_header
        yield csv
      end
    end

    def summary_table(counts)
      head = %w[entity local cb matched identical changed cb-only local-only]
      rows = counts.map do |c|
        [c[:entity], c[:local], c[:cb], c[:matched], c[:identical], c[:changed], c[:cb_only], c[:local_only]]
      end
      widths = head.each_index.map { |i| ([head[i]] + rows.map { |r| r[i].to_s }).map(&:length).max }
      fmt = ->(r) { r.each_with_index.map { |v, i| v.to_s.ljust(widths[i]) }.join("  ") }
      ([fmt.call(head)] + rows.map { |r| fmt.call(r) }).join("\n")
    end
  end
end
```

- [ ] **Step 2: Write the Reconciler**

Create `app/services/chulabooster/reconciler.rb`:

```ruby
require "json"

module Chulabooster
  class Reconciler
    def initialize(client:, writer:, run_dir:)
      @client = client
      @writer = writer
      @run_dir = run_dir
    end

    def reconcile_entity(mapper, start_cursor: nil)
      entity = mapper.entity
      local = mapper.local_scope.index_by { |rec| mapper.local_key(rec) }
      seen = load_seen(entity)
      counts = { entity: entity, local: local.size, cb: 0, matched: 0, identical: 0, changed: 0, cb_only: 0, local_only: 0 }

      @client.each_page(entity, start_cursor: start_cursor) do |rows, next_cursor|
        changed_rows = []
        cb_only_rows = []
        new_seen = []
        rows.each do |cb_row|
          counts[:cb] += 1
          key = mapper.cb_key(cb_row)
          rec = local[key]
          if rec.nil?
            counts[:cb_only] += 1
            cb_only_rows << { key: key, identifiers: mapper.identifiers(cb_row) }
          else
            counts[:matched] += 1
            new_seen << key
            diffs = mapper.field_diffs(rec, cb_row)
            if diffs.empty?
              counts[:identical] += 1
            else
              counts[:changed] += 1
              changed_rows << { key: key, diffs: diffs }
            end
          end
        end
        @writer.append_changed(entity, changed_rows) if changed_rows.any?
        @writer.append_cb_only(entity, cb_only_rows) if cb_only_rows.any?
        append_seen(entity, new_seen)
        new_seen.each { |k| seen << k }
        write_checkpoint(entity, next_cursor)
      end

      local_only = local.keys - seen.to_a
      counts[:local_only] = local_only.size
      @writer.append_local_only(entity, local_only)
      write_checkpoint(entity, nil, done: true)
      counts
    end

    private

    def checkpoint_path = File.join(@run_dir, "checkpoint.json")

    def write_checkpoint(entity, next_cursor, done: false)
      File.write(checkpoint_path, JSON.pretty_generate(entity: entity, next_cursor: next_cursor, done: done))
    end

    def load_seen(entity)
      path = @writer.seen_path(entity)
      set = Set.new
      File.foreach(path) { |line| set << JSON.parse(line.chomp) } if File.exist?(path)
      set
    end

    def append_seen(entity, keys)
      File.open(@writer.seen_path(entity), "a") { |f| keys.each { |k| f.puts(JSON.generate(k)) } }
    end
  end
end
```

- [ ] **Step 3: Write the tests**

Create `test/services/chulabooster/reconciler_test.rb`:

```ruby
require "test_helper"
require "tmpdir"

class Chulabooster::ReconcilerTest < ActiveSupport::TestCase
  # A client stub whose each_page yields canned pages for one entity.
  class FakeClient
    def initialize(pages) = @pages = pages   # [[rows, next_cursor], ...]
    def each_page(_entity, start_cursor: nil)
      @pages.each { |rows, cursor| yield rows, cursor }
    end
  end

  setup do
    @dir = Dir.mktmpdir("recon-test")
    @writer = Chulabooster::ReportWriter.new(@dir)
  end
  teardown { FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir) }

  test "buckets identical / changed / cb_only / local_only for programs" do
    p = programs(:cp_bachelor)
    identical = { "program_id" => p.program_code, "program_name" => p.name_en, "program_name_alt" => p.name_th,
                  "revision_year" => p.year_started - 543, "program_code" => p.alternative_program_code }
    changed = { "program_id" => programs(:cp_master).program_code, "program_name" => "X",
                "program_name_alt" => "Y", "revision_year" => 2000, "program_code" => "Z" }
    cb_only = { "program_id" => "999999999999", "program_name" => "Ghost" }
    client = FakeClient.new([[[identical, changed], "c1"], [[cb_only], nil]])

    counts = Chulabooster::Reconciler.new(client: client, writer: @writer, run_dir: @dir)
                                     .reconcile_entity(Chulabooster::Mappers::Programs.new)

    assert_equal Program.count, counts[:local]
    assert_equal 3, counts[:cb]
    assert_equal 1, counts[:identical]
    assert_equal 1, counts[:changed]
    assert_equal 1, counts[:cb_only]
    assert_equal Program.count - 2, counts[:local_only] # all locals except the two matched
    assert_path_exists File.join(@dir, "programs_changed.csv")
    assert_path_exists File.join(@dir, "programs_cb_only.csv")
    assert_path_exists File.join(@dir, "checkpoint.json")
  end

  test "reconcile writes nothing to the database (read-only)" do
    client = FakeClient.new([[[{ "program_id" => "999999999999", "program_name" => "Ghost" }], nil]])
    assert_no_difference ["Program.count", "ProgramCourse.count", "Course.count", "Student.count", "Grade.count"] do
      Chulabooster::Reconciler.new(client: client, writer: @writer, run_dir: @dir)
                              .reconcile_entity(Chulabooster::Mappers::Programs.new)
    end
  end

  test "write_summary produces summary.md and a console table" do
    counts = [{ entity: "programs", local: 46, cb: 260, matched: 44, identical: 40, changed: 4, cb_only: 216, local_only: 2 }]
    table = @writer.write_summary(counts)
    assert_match "programs", table
    assert_path_exists File.join(@dir, "summary.md")
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/services/chulabooster/reconciler_test.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
hg add app/services/chulabooster/report_writer.rb app/services/chulabooster/reconciler.rb \
  test/services/chulabooster/reconciler_test.rb
hg commit app/services/chulabooster/report_writer.rb app/services/chulabooster/reconciler.rb \
  test/services/chulabooster/reconciler_test.rb \
  -m "Diff one entity read-only and stream results to files: the reconciler buckets each CB row against local records and the report writer appends CSVs + a per-page checkpoint"
```

---

### Task 5: `chulabooster:reconcile` rake task (orchestration + resume)

**Files:**
- Create: `lib/tasks/chulabooster.rake`
- Test: `test/services/chulabooster/reconcile_task_test.rb`

**Interfaces:**
- Consumes: `Client`, `Reconciler`, `ReportWriter`, all five mappers.
- Produces: `bin/rails chulabooster:reconcile` (fresh run into `tmp/reconciliation/<timestamp>/`) and `RESUME=<dir> bin/rails chulabooster:reconcile` (skip completed entities, resume in-progress from `checkpoint.json`). Exposes `Chulabooster.mappers -> [Mappers::*]` for reuse/testing.

- [ ] **Step 1: Add the mapper registry**

Create `app/services/chulabooster.rb`:

```ruby
require "json"

module Chulabooster
  MAPPERS = %w[Programs Courses Students ProgramCourses StudentCourses].freeze

  def self.mappers = MAPPERS.map { |name| Mappers.const_get(name).new }

  # Reads any prior checkpoint.json in run_dir to decide what to skip/resume. Completed entities are
  # inferred from the presence of each entity's *_local_only.csv (written only at completion).
  def self.load_checkpoint(run_dir)
    cp_path = File.join(run_dir, "checkpoint.json")
    completed = mappers.map(&:entity).select { |e| File.exist?(File.join(run_dir, "#{e}_local_only.csv")) }
    data = File.exist?(cp_path) ? JSON.parse(File.read(cp_path), symbolize_names: true) : {}
    in_progress = (data[:done] == false) ? data[:entity] : nil
    { completed: completed, in_progress: in_progress, next_cursor: data[:next_cursor] }
  end
end
```

- [ ] **Step 2: Write the rake task**

Create `lib/tasks/chulabooster.rake`:

```ruby
namespace :chulabooster do
  desc "Read-only reconciliation of ChulaBooster exports vs local DB. RESUME=tmp/reconciliation/<ts> to resume."
  task reconcile: :environment do
    $stdout.sync = true

    resume_dir = ENV["RESUME"]
    run_dir = resume_dir || Rails.root.join("tmp", "reconciliation", Time.zone.now.strftime("%Y%m%d-%H%M%S")).to_s
    writer  = Chulabooster::ReportWriter.new(run_dir)
    client  = Chulabooster::Client.new
    reconciler = Chulabooster::Reconciler.new(client: client, writer: writer, run_dir: run_dir)

    checkpoint = Chulabooster.load_checkpoint(run_dir)
    counts = []

    Chulabooster.mappers.each do |mapper|
      entity = mapper.entity
      if checkpoint[:completed].include?(entity)
        puts "= #{entity}: already complete, skipping"
        next
      end
      start_cursor = (checkpoint[:in_progress] == entity) ? checkpoint[:next_cursor] : nil
      puts "→ #{entity}#{start_cursor ? " (resuming)" : ""}..."
      counts << reconciler.reconcile_entity(mapper, start_cursor: start_cursor)
      checkpoint[:completed] << entity
    end

    puts "\n#{writer.write_summary(counts)}\n\n→ files: #{run_dir}"
  end
end
```

- [ ] **Step 3: Write the test**

Create `test/services/chulabooster/reconcile_task_test.rb`:

```ruby
require "test_helper"
require "tmpdir"

class Chulabooster::ReconcileTaskTest < ActiveSupport::TestCase
  test "load_checkpoint marks entities with a local_only.csv as completed" do
    Dir.mktmpdir("recon-task") do |dir|
      File.write(File.join(dir, "programs_local_only.csv"), "key\n")
      File.write(File.join(dir, "checkpoint.json"),
                 { entity: "courses", next_cursor: "abc", done: false }.to_json)
      cp = Chulabooster.load_checkpoint(dir)
      assert_includes cp[:completed], "programs"
      assert_equal "courses", cp[:in_progress]
      assert_equal "abc", cp[:next_cursor]
    end
  end

  test "mappers registry returns all five in order" do
    assert_equal %w[programs courses students program_courses student_courses],
                 Chulabooster.mappers.map(&:entity)
  end
end
```

- [ ] **Step 4: Run the test + full suite**

Run: `bin/rails test test/services/chulabooster/reconcile_task_test.rb`
Expected: pass.
Run: `bin/rails test`
Expected: full suite green (no regressions).

- [ ] **Step 5: Commit**

```bash
hg add app/services/chulabooster.rb lib/tasks/chulabooster.rake test/services/chulabooster/reconcile_task_test.rb
hg commit app/services/chulabooster.rb lib/tasks/chulabooster.rake \
  test/services/chulabooster/reconcile_task_test.rb \
  -m "Run the full read-only reconciliation from the CLI: a chulabooster:reconcile rake task that walks all five entities, writes report files, and resumes an interrupted run via RESUME=<dir>"
```

---

## Notes for the implementer

- **Read-only is the cardinal rule.** If any step tempts you to persist CB data, stop — that's the later write-back phase, out of scope here.
- **Fixtures for tests:** `programs(:cp_bachelor)` = code `"2101"`, `programs(:cp_master)` = `"2102"`; `courses(:intro_computing)` = `("2110101", 2565)`, linked to `cp_bachelor` via `program_courses.yml`; `grades.yml` has grades. Verify the exact `students.yml` fixture name in Task 2 Step 6.
- **The `matched` count is the diagnostic:** if a real run shows near-zero matches for `student_courses`, the `semester_code`/`section` encodings are off (expected — the dry run exists to surface exactly this).
- **Manual smoke (optional, real API, read-only):** `bin/rails chulabooster:reconcile` — the four fast entities finish in minutes; the grades pass runs long (page it, `nohup` if needed).
