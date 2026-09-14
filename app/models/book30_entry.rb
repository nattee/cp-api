# A printed line of the 30-year book's alumni directory and the decision taken
# about it. Outcome vocabulary and rules: docs/book30-import-report.md.
class Book30Entry < ApplicationRecord
  LINK_OUTCOMES   = %w[linked_exact linked_variant linked_other_year].freeze
  IGNORE_OUTCOMES = %w[second_listing duplicate_line unparsed].freeze
  CREATE_OUTCOMES = %w[create_book_only_cohort create_missing create_lost_claim create_namesake].freeze
  OUTCOMES = (LINK_OUTCOMES + IGNORE_OUTCOMES + CREATE_OUTCOMES).freeze

  OUTCOME_LABELS = {
    "linked_exact"            => "Confirmed",
    "linked_variant"          => "Near match, DB name kept",
    "linked_other_year"       => "Same name, neighbouring year",
    "second_listing"          => "Second listing of a known person",
    "duplicate_line"          => "Duplicate line",
    "unparsed"                => "Unparsed line",
    "create_book_only_cohort" => "Created: cohort absent from DB",
    "create_missing"          => "Created: no candidate in cohort",
    "create_lost_claim"       => "Created: lost a shared claim",
    "create_namesake"         => "Created: namesake only"
  }.freeze

  OUTCOME_FAMILY = (
    LINK_OUTCOMES.to_h { |o| [o, "link"] }
      .merge(IGNORE_OUTCOMES.to_h { |o| [o, "ignore"] })
      .merge(CREATE_OUTCOMES.to_h { |o| [o, "create"] })
  ).freeze

  belongs_to :student, optional: true

  validates :cohort, :year_be, :line_no, :raw_line, :outcome, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :line_no, uniqueness: { scope: :cohort }

  scope :linked,  -> { where(outcome: LINK_OUTCOMES) }
  scope :created, -> { where(outcome: CREATE_OUTCOMES) }

  def family
    OUTCOME_FAMILY[outcome]
  end

  def prefix
    cohort[0, 2]
  end
end
