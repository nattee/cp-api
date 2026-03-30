# Schedule Scraper

**Status: Implemented**

Fetch course schedule data from external sources and import it into the teaching schedule system. This is an alternative to CSV import — automated data collection from publicly available university websites.

See `docs/teaching-schedule.md` for the data model.

## Architecture

The scraper system supports multiple data source backends behind a common interface. Each backend fetches raw schedule data and normalizes it into a common format, which is then fed into the same creation logic as the CSV importer.

```
┌─────────────────────────┐
│   ScraperController     │  User picks: source, semester
│   (UI + job trigger)    │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│   ScheduleScrapeJob     │  Background job (ActiveJob)
│                         │
│  For each Course in DB: │
│    source.fetch_course()│
│    → normalize → import │
│    (rate limited)       │
└───────────┬─────────────┘
            │
   ┌────────┴────────┐
   ▼                 ▼
┌──────────┐  ┌──────────────┐
│ CuGetReg │  │ ChulaReg     │
│ (GraphQL)│  │ (HTML scrape)│
└──────────┘  └──────────────┘
```

### High-level driver

The scrape job iterates over **all courses in our database** for the given semester. No manual course prefix input — the system knows which courses we track.

```ruby
# Pseudocode for the job
courses = Course.all
courses.each do |course|
  data = source.fetch_course(course.course_no, semester, study_program)
  next if data.nil?  # course not offered this semester
  import_course_data(data, semester)
  sleep(1.0 / rate_limit)  # rate limiting
end
```

### Common interface

Each scraper backend implements:

```ruby
module Scrapers
  class Base
    def initialize(semester:, study_program:)
      @semester = semester            # Semester record
      @study_program = study_program  # "S", "T", or "I"
    end

    # Returns a single normalized course hash (see format below), or nil if not found
    def fetch_course(course_no)
      raise NotImplementedError
    end

    def source_name
      raise NotImplementedError
    end
  end
end
```

### Rate limiting

Configured in `config/scraper.yml`:

```yaml
default: &default
  rate_limit: 10          # requests per second
  request_timeout: 10     # seconds per request
  retry_count: 3          # retries on transient failure
  retry_delay: 2          # seconds between retries

development:
  <<: *default

production:
  <<: *default
  rate_limit: 5           # more conservative in production
```

Loaded via `Rails.application.config_for(:scraper)`.

### Normalized format

Every backend returns the same structure for a single course:

```ruby
{
  course_no: "2110327",
  name_en: "ALGORITHM DESIGN",
  name_th: "การออกแบบอัลกอริทึม",
  description_en: "...",          # nil if source doesn't provide
  description_th: "...",          # nil if source doesn't provide
  credits: 3.0,
  sections: [
    {
      section_no: "1",
      note: "2CP",
      enrollment_current: 58,
      enrollment_max: 60,
      classes: [
        {
          type: "LECT",           # LECT, LAB, etc.
          day: "MO",              # MO, TU, WE, TH, FR, SA, SU
          start_time: "09:30",
          end_time: "11:00",
          building: "ENG3",
          room: "409",
          teachers: ["NNN"]       # Initials (both sources only provide initials)
        }
      ]
    }
  ]
}
```

### Import logic

The normalized data feeds into the same find-or-create logic as `ScheduleImporter`:

1. **Course**: find by `course_no` (must exist in our system already — skip if not). Update `description`/`description_th` if blank and source provides them.
2. **CourseOffering**: find-or-create by course + semester
3. **Section**: find-or-create by offering + section_number. Update `enrollment_current`, `enrollment_max`, `remark`.
4. **TimeSlot**: find-or-create by section + day + start_time + end_time, attach room
5. **Room**: find-or-create by building + room_number
6. **Teaching**: find-or-create by section + staff (if initials can be resolved via `Staff#initials`)

Courses not in our database are **skipped** (logged but not created) — we only import schedule data for courses we already track.

## Source 1: CuGetReg (Recommended)

Student-built alternative frontend at `cugetreg.com`. Provides a **GraphQL API** with clean, structured JSON data.

### Endpoint

```
POST https://cugetreg.com/_api/graphql
Content-Type: application/json
```

No authentication required. UTF-8 encoding. Likely rate limited but no explicit documentation.

### Key queries

**Search courses by prefix:**
```graphql
{
  search(
    filter: { keyword: "2110", limit: 50, offset: 0 }
    courseGroup: { semester: "2", academicYear: "2567", studyProgram: S }
  ) {
    courseNo courseNameEn courseNameTh credit
    sections {
      sectionNo closed note
      capacity { current max }
      classes {
        type dayOfWeek
        period { start end }
        building room teachers
      }
    }
  }
}
```

**Fetch single course:**
```graphql
{
  course(
    courseNo: "2110327"
    courseGroup: { semester: "2", academicYear: "2567", studyProgram: S }
  ) {
    courseNo courseNameEn courseNameTh credit
    sections { ... }
  }
}
```

### Data mapping

| GraphQL field | Our field |
|---------------|-----------|
| `courseNo` | `course_no` |
| `courseNameEn` | `name_en` |
| `courseNameTh` | `name_th` |
| `credit` | `credits` |
| `sections[].sectionNo` | `section_number` |
| `sections[].note` | `section.remark` |
| `sections[].classes[].dayOfWeek` | `day_of_week` (MO→1, TU→2, etc.) |
| `sections[].classes[].period.start` | `start_time` |
| `sections[].classes[].period.end` | `end_time` |
| `sections[].classes[].building` | `room.building` |
| `sections[].classes[].room` | `room.room_number` |
| `sections[].classes[].teachers` | staff initials (needs resolution) |

### academicYear note

CuGetReg uses **CE year** (e.g., `"2567"` is B.E. — need to verify whether this field is CE or B.E.). The search form URL path uses `S` for ทวิภาค study program. Based on our test query, `academicYear: "2567"` returned data for B.E. 2567 (CE 2024), so the field appears to use **B.E. year as a string**.

### Advantages
- Clean JSON, no HTML parsing
- No session cookies needed
- Paginated search support
- UTF-8 encoding
- Includes Thai course names

### Risks
- Third-party student project — could go down or change API without notice
- Data freshness depends on how often they sync from the official source
- No SLA or rate limit documentation

## Source 2: CAS Reg Chula (Official)

The official university course schedule system at `cas.reg.chula.ac.th`. HTML-based, frameset architecture from the late 1990s.

### Flow

The servlet package prefix is `com.dtm.chula.cs.servlet.QueryCourseScheduleNew`. Full paths:

1. **Initialize session**: `GET /servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.QueryCourseScheduleNewServlet` (get cookies)
2. **Search (course list)**: `GET /servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.CourseListNewServlet?studyProgram=S&semester=2&acadyearEfd=2568&courseno=2110&acadyear=2568&lang=T` — must be called before detail to set server-side session state
3. **Detail**: `GET /servlet/com.dtm.chula.cs.servlet.QueryCourseScheduleNew.CourseScheduleDtlNewServlet?courseNo=2110327&studyProgram=S&semester=2&acadyear=2568` → returns section/time/room table

The entry point HTML page is at `/cu/cs/QueryCourseScheduleNew/index.html` (frameset that loads the servlet).

### Key details
- **Requires session cookie** from step 1 before queries work
- **TIS-620 encoding** (Thai legacy) — needs `iconv` conversion to UTF-8
- **SSL certificate issues** — invalid cert, must skip verification
- **Rate limiting**: 5-second cooldown enforced by JS (likely server-side too)
- **First request often fails** with "ระบบยังไม่พร้อมใช้งาน" — need retry logic
- **HTML parsing**: course list is `<A HREF=...>courseNo</A>` links, detail page is a `<TABLE>` with sections as `<TR>` rows

### HTML parsing (detail page)

The detail table has these columns:
```
ตอนเรียน | วิธีสอน | วัน-เวลาเรียน | อาคาร | ห้อง | ผู้สอน | หมายเหตุ | จำนวนนิสิต
section  | method | day  | time  | building | room | teacher | remark | enrollment
```

Days are inline text (MO, TU, WE, etc. within the same `<TD>`), time is a separate cell. Needs Nokogiri for parsing.

**Malformed HTML warning**: The detail table (`#Table3`) has unclosed `<TD>` tags. Starting from the second section row, cell[1] (section number) contains the section number concatenated with all subsequent cell content (e.g. `"2 LECT TH 8:00-11:00 ENG3 219 NPS ..."`). The parser extracts only the leading digits from cell[1] via regex.

**Additional data available**: CAS Reg also provides Thai course name, English course name, and credits (parsed from `#Table2` and the credit table). It does not provide course descriptions.

### Advantages
- Official source — authoritative data
- Updated daily
- No third-party dependency risk

### Risks
- Fragile: any layout change breaks the parser
- Session management and rate limiting add complexity
- TIS-620 encoding is a pain
- Intermittent "system unavailable" errors need retry handling

## Teacher Initials

**Both sources only provide teacher initials** (e.g., "NNN", "PKY"), not full names. This is a universal limitation from the registration system.

### Staff model change

Add `initials` as a regular field on Staff (like `email` or `phone` — just another attribute of the staff member):

```ruby
# Migration
add_column :staffs, :initials, :string
add_index :staffs, :initials, unique: true
```

```ruby
# Staff model
validates :initials, uniqueness: true, allow_nil: true
```

Admin sets initials on the Staff edit form (one-time setup per staff member). Could auto-suggest from name initials as a starting guess.

### Lookup during import

1. `Staff.find_by(initials: teacher_initials)` — exact match
2. If no match → log as unresolved, skip Teaching record (don't fail the import)

## UI

### Scraper page

Accessible from the "Teaching" sidebar section (or from the Semester show page).

**URL**: `GET /scrapes/new`

**Form fields:**
- Semester (Select2 dropdown)
- Study program: ทวิภาค (S) / ทวิภาค นานาชาติ (I)
- Source: CuGetReg (recommended) / CAS Reg Chula

No course prefix input — the job automatically fetches all courses in our database.

**Actions:**
- "Preview" — dry run on a sample of courses, show what would be imported + unresolved teachers
- "Import" — queue the background job for all courses

### Results page

**URL**: `GET /scrapes/:id`

Shows:
- Status (queued/running/completed/failed)
- Courses found / imported / skipped (not in our system)
- Sections created/updated
- Time slots created/updated
- Unresolved teacher initials (with a prompt to add them to Staff records)
- Error log

## Data Model

### scrapes table

| Column              | Type    | Constraints |
|---------------------|---------|-------------|
| semester_id         | bigint  | not null, FK semesters |
| user_id             | bigint  | not null, FK users |
| source              | string  | not null ("cugetreg" or "cas_reg") |
| study_program       | string  | not null ("S", "T", "I") |
| state               | string  | not null (pending/running/completed/failed) |
| total_courses       | integer | default 0 |
| courses_found       | integer | default 0 |
| courses_not_found   | integer | default 0 |
| sections_count      | integer | default 0 |
| time_slots_count    | integer | default 0 |
| unresolved_teachers | json    | nullable (array of initials) |
| error_log           | json    | nullable (array of {course_no, error}) |
| error_message       | text    | nullable |
| timestamps          |         | |

### courses table changes (implemented)

Description columns added: `description` (text), `description_th` (text). Populated from CuGetReg which provides `courseDescTh`/`courseDescEn`.

### sections table changes (implemented)

Enrollment columns added: `enrollment_current` (integer), `enrollment_max` (integer). Updated on each scrape.

### staffs table change (implemented)

Column added: `initials` (string, unique index). Admin sets via Staff edit form.

## Three Ways to Run

### 1. Web UI (admin)

```ruby
# routes
resources :scrapes, only: [:new, :create, :show, :index]
```

**Flow**: admin fills form (`/scrapes/new`) → `create` queues `ScheduleScrapeJob` → redirects to `/scrapes/:id`

**Progress**: the show page displays the Scrape record's state and counts. While `state == "running"`, the page auto-refreshes via `<meta http-equiv="refresh" content="3">` (simple, no WebSocket/Turbo Stream needed). The job updates the Scrape record after each course:

```ruby
# Inside ScheduleScrapeJob, after each course:
scrape.update!(
  courses_found: courses_found,
  courses_not_found: courses_not_found,
  sections_count: sections_count,
  time_slots_count: time_slots_count
)
```

When the job finishes, state becomes `completed` or `failed`, and the page stops refreshing.

**Index page** (`/scrapes`) shows history of past scrapes with date, semester, source, counts.

### 2. Rake task (terminal / cron)

```
$ bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=2
Scraping 2568/2 via cugetreg (87 courses)...
  [1/87]  2110101  ✓ 3 sections, 6 time slots
  [2/87]  2110201  ✓ 2 sections, 4 time slots
  [3/87]  2110211  — not found this semester
  [4/87]  2110215  ✗ timeout (will retry)
  ...
Done. 82 found, 5 not offered, 0 errors.
Unresolved teachers: NNN, SRS
```

Runs synchronously, prints progress line by line. Also creates a Scrape record for history. Good for:
- Cron jobs (`0 6 * * * cd /app && bin/rails scraper:run SOURCE=cugetreg YEAR=2568 SEMESTER=2`)
- Debugging in the terminal
- Running from scripts

**Arguments:**
- `SOURCE` — `cugetreg` (default) or `cas_reg`
- `YEAR` — B.E. year (required)
- `SEMESTER` — 1, 2, or 3 (required)
- `PROGRAM` — study program, default `S`

### 3. Console helper (dev / debugging)

For quick testing in `rails console`:

```ruby
# Scrape a single course (hits real server, no stub)
Scrapers::CuGetReg.scrape("2110327", 2568, 2)
# => returns normalized hash for that course

# Scrape and import a single course into the database
Scrapers::CuGetReg.scrape!("2110327", 2568, 2)
# => finds-or-creates CourseOffering, Sections, TimeSlots, etc.
# => returns a summary hash { sections: 4, time_slots: 8, ... }

# Scrape from official source
Scrapers::CasReg.scrape("2110327", 2568, 2)
```

These are **class methods** that bypass the job queue — synchronous, return results directly. Useful for:
- Verifying the scraper works against the live server
- Debugging parsing issues for a specific course
- Quick one-off imports without the full UI flow

The arguments are `(course_no, year_be, semester_number)`. Study program defaults to `"S"`, optional 4th argument.

## Development & Stubbing

**Dev mode** hits real servers by default — the scraper targets public URLs (cugetreg.com, cas.reg.chula.ac.th) accessible from any machine with internet. Use the console helpers (`Scrapers::CuGetReg.scrape(...)`) for quick testing.

**Test mode** uses stub/fixtures — never hits real servers:

```yaml
# config/scraper.yml
development:
  <<: *default
  # stub: false (default — hits real servers)

test:
  <<: *default
  stub: true    # use fixture files instead of real HTTP
```

When `stub: true`, backends read from fixture files in `test/fixtures/scraper/` instead of making HTTP requests:
- `test/fixtures/scraper/cugetreg/2110327.json` — sample GraphQL response
- `test/fixtures/scraper/cas_reg/2110327.html` — sample HTML detail page (TIS-620 encoded)

This lets tests run in CI without network access.

## Failure Handling

**Per-course failure**: if a single course fetch fails (timeout, 500, parse error), log it as an `ApiEvent` warning and continue to the next course. Don't abort the whole job.

**Source completely down**: after `retry_count` retries with `retry_delay` backoff, mark that course as failed and continue. If every course fails, the job completes with an error summary.

**No automatic fallback** between sources. The user chose the source; if CuGetReg is down, they can manually re-run with CAS Reg. Automatic fallback adds complexity (different parsers, different session requirements) for little benefit since both sources rarely go down simultaneously.

## Source Comparison

Both sources provide **equivalent schedule data** — they're fed by the same university registration system.

| Data | CuGetReg | CAS Reg | We use it? |
|------|----------|---------|------------|
| Course no, name EN/TH, credits | yes | yes | yes |
| **Course descriptions EN/TH** | **yes** | no | **yes** (update Course model) |
| Sections (number, note, enrollment) | yes | yes | yes |
| Time slots (day, time, building, room) | yes | yes | yes |
| Teacher initials | yes | yes | yes |
| Midterm/final exam dates | yes | yes | not yet |
| Section `closed` flag | yes | no | not yet |
| Student ratings/reviews | yes | no | no |

For schedule import, they're mostly interchangeable. **CuGetReg is the recommended primary source** — clean GraphQL API, no session cookies, no encoding issues, plus course descriptions that CAS Reg doesn't have. CAS Reg is the fallback for when CuGetReg is unavailable or if we need the official source for audit reasons.

## Implementation Order

1. **Staff initials column** — migration + model update + admin UI to set initials
2. **Scraper base class** + normalized format
3. **CuGetReg backend** — GraphQL client, normalize response (recommended first — cleaner API, easier to implement)
4. **Scraper job + controller + UI** — form, preview, import, results
5. **CAS Reg backend** — session management, HTML parsing with Nokogiri, TIS-620 decoding, retry logic (implement second — more complex)

## Testing

All tests use stub mode — fixture files in `test/fixtures/scraper/`, no real HTTP.

### Unit tests
- **CuGetReg scraper**: load fixture JSON, verify normalized output matches expected format
- **CAS Reg scraper**: load fixture HTML (TIS-620 encoded), verify parsing and normalization
- **Import logic**: given normalized data, verify find-or-create for CourseOffering, Section (with enrollment), TimeSlot, Room, Teaching
- **Teacher initials resolution**: match found, no match (logged but not failed), nil/blank teachers
- **Rate limiting**: verify delay between requests respects config
- **Failure handling**: stub a timeout/500 for one course, verify job continues and logs error

### System tests
- Admin can start a scrape (with stub mode)
- Flash message confirms job was queued
- ApiEvent log shows scrape results after completion

## Design Decisions

1. **Rate limit**: 10 req/sec default, configurable via `config/scraper.yml`. More conservative in production (5 req/sec).
2. **CuGetReg data freshness**: next-day sync from official source. Acceptable for our use case.
3. **Scrape scope**: the job iterates over all courses in our database — no manual course prefix. This ensures complete coverage.
4. **Enrollment data**: stored on the Section model (`enrollment_current`, `enrollment_max`). Updated on each scrape.
5. **Teacher initials**: a regular field on Staff (`initials` column), set by admin. Not a separate mapping table.
