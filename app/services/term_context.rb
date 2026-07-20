# The user's current working term, as a value object. Resolves from the session
# and, when unset or stale, from the latest semester on record. It only ever
# supplies DEFAULTS to report forms — it never changes what a report computes.
#
# The canonical unit is (academic_year_be, semester_number), matching how the app
# stores a Thai academic year (year_be) rather than a calendar year. semester_number
# may be nil, meaning "whole year". The pair is stored, not a Semester#id, so a
# year-level report works even when that specific semester row does not exist.
class TermContext
  attr_reader :academic_year_be, :semester_number

  def self.from_session(session)
    stored = session[:term_context]
    year = stored && stored["year_be"]
    if year.present? && Semester.exists?(year_be: year)
      new(academic_year_be: year.to_i, semester_number: stored["semester"]&.to_i)
    else
      default
    end
  end

  def self.default
    latest = Semester.ordered.first
    new(academic_year_be: latest&.year_be, semester_number: latest&.semester_number)
  end

  def initialize(academic_year_be:, semester_number:)
    @academic_year_be = academic_year_be
    @semester_number = semester_number
  end

  # The Semester row for this exact pair, or nil if none exists (e.g. a summer
  # that was never created). Callers treat nil as "unspecified".
  def semester_record
    return nil unless academic_year_be && semester_number
    Semester.find_by(year_be: academic_year_be, semester_number: semester_number)
  end

  def present?
    academic_year_be.present?
  end
end
