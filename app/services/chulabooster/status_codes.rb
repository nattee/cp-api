module Chulabooster
  # Crosswalk from CB's raw student_status codes to our Student::STATUSES values.
  # Empirically derived and validated (~99% against locally-confirmed graduated/
  # retired students) — see docs/chulabooster-student-status-crosswalk.md.
  # CB has never documented these codes; unknown codes map to nil so callers
  # can fall back to "unknown" and report, never crash.
  module StatusCodes
    ACTIVE    = %w[00 01 05].freeze
    GRADUATED = %w[11 12 13].freeze
    RETIRED   = %w[21 23 24 25 27 28 30 31 32 33 35 36 37 39].freeze

    def self.to_local(code)
      c = code.to_s.strip
      return "active"    if ACTIVE.include?(c)
      return "graduated" if GRADUATED.include?(c)
      return "retired"   if RETIRED.include?(c)
      nil
    end
  end
end
