# Describes every path by which data enters cp-api.
#
# This is a PORO, not an ActiveRecord model — there is no data_sources table. It is
# the single source of truth for the /data_sources page.
#
# Each entry MUST state both what the source provides and what it does NOT provide.
# `not_provides` is the reason this page exists: the two facts recorded below each
# cost a full working session to rediscover.
class DataSource
  SOURCES = [
    {
      key: "imports",
      name: "CSV / Excel Imports",
      icon: "upload_file",
      badge: "manual_upload",
      blurb: "Multi-step upload, then column mapping, then execute. An import stays pending " \
             "until you confirm the mapping; failed imports can be retried.",
      provides: [
        "Any entity with an importer registered in DataImport::IMPORTERS"
      ],
      not_provides: [
        "Nothing automatic — one file per import, with the column mapping confirmed by a human"
      ],
      caution: nil,
      action: { label: "Go to Imports", path: :data_imports_path },
      commands: [],
      docs: []
    },
    {
      key: "chulabooster",
      name: "ChulaBooster",
      icon: "sync",
      badge: "console_only",
      blurb: "The university registrar system. A read-only client plus reconciler: every sync " \
             "is a dry-run by default and writes only with COMMIT=1.",
      provides: [
        "Programs, courses, and students",
        "Grades (CB calls these student_courses)",
        "Program-to-course pairings"
      ],
      not_provides: [
        "Course offerings, sections, time slots, rooms, teachers — CB has no such entity, " \
        "and student_courses.section is null in every row",
        "Current-semester data — CB is populated after a term ends, so it lags roughly one semester"
      ],
      caution: nil,
      action: nil,
      commands: [
        "bin/rails chulabooster:snapshot                       # cache a full CB pull (~40 min, resumable)",
        "bin/rails chulabooster:sync_students SNAPSHOT_DIR=tmp/chulabooster_snapshot/<ts>   # DRY-RUN (default)",
        "bin/rails chulabooster:sync_students SNAPSHOT_DIR=... COMMIT=1                     # actually write",
        "bin/rails chulabooster:sync_courses / sync_grades / sync_program_courses",
        "",
        "# Dry-run report CSVs land in tmp/chulabooster_sync/<timestamp>/ — review before committing."
      ],
      docs: [
        "docs/chulabooster-client-guide.md",
        "docs/chulabooster-program-crosswalk.md",
        "docs/chulabooster-student-status-crosswalk.md"
      ]
    },
    {
      key: "cugetreg",
      name: "CuGetReg",
      icon: "cloud_sync",
      badge: "recommended",
      blurb: "GraphQL API. The source of record for teaching schedules.",
      provides: [
        "Course offerings, sections, and time slots",
        "Rooms and teacher initials",
        "Enrollment counts (current / max)"
      ],
      not_provides: [
        "Grades and student records",
        "Program structure"
      ],
      caution: nil,
      action: { label: "Run a scrape", path: :scrapes_path },
      commands: [
        "bin/rails scraper:run SOURCE=cugetreg YEAR=2569 SEMESTER=2",
        "# optional: PROGRAM=S|I (default S), LIMIT=n to smoke-test first"
      ],
      docs: ["docs/schedule-scraper.md"]
    },
    {
      key: "cas_reg",
      name: "reg.chula (CAS Reg)",
      icon: "travel_explore",
      badge: "verify_only",
      blurb: "HTML scrape of cas.reg.chula.ac.th. A cross-check for CuGetReg — not an import source.",
      provides: [
        "The same shape as CuGetReg: offerings, sections, and time slots"
      ],
      not_provides: [
        "A safe import path — see the warning below"
      ],
      caution: "Do not import from this source. It collapses a twice-weekly class into a single " \
               'row with day: "TU TH". Scrapers::Base#parse_day looks that up in DAY_MAP, gets nil, ' \
               'and its "next if day.nil?" guard silently skips the slot — the meeting is lost. It also ' \
               "overwrites Section enrollment last-writer-wins. Use Scrapers::CasReg.scrape " \
               "(read-only) to verify CuGetReg — never scrape!",
      action: nil,
      commands: [
        %q{bin/rails runner 'pp Scrapers::CasReg.scrape("2110200", 2569, 1)'   # read-only cross-check}
      ],
      docs: ["docs/schedule-scraper.md"]
    }
  ].freeze

  def self.all
    SOURCES
  end

  def self.find(key)
    SOURCES.find { |source| source[:key] == key }
  end
end
