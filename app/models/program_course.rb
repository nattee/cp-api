class ProgramCourse < ApplicationRecord
  belongs_to :program
  belongs_to :course

  # Curriculum group labels, keyed by FULL course_group_code — per-program mapping,
  # so "4784-C" and "3736-C" are separate entries by design (programs may disagree
  # on a suffix's meaning). See docs/superpowers/specs/2026-07-06-course-group-display-design.md.
  #
  # HASH INSERTION ORDER = DISPLAY ORDER of groups on the program curriculum page.
  #
  # Entries whose label equals the raw suffix (e.g. "MS") mean the university's
  # meaning is unconfirmed — the raw suffix is shown until a real name is supplied.
  # Unknown codes not listed here render as their raw suffix automatically (see
  # .group_label), so new CB data never breaks the page.
  COURSE_GROUP_LABELS = {
    # CP 2566 curriculum (program_code 4784)
    "4784-C"     => "Compulsory",
    "4784-ELEC"  => "Elective",
    "4784-MS"    => "MS",
    "4784-ENG"   => "English",
    "4784-GLANG" => "GLANG",
    "4784-GSP"   => "GSP",
    "4784-SP"    => "SP",
    "4784-21"    => "21",
    # CP 2561 curriculum (program_code 3736)
    "3736-C"     => "Compulsory",
    "3736-ELEC"  => "Elective",
    "3736-ELEC2" => "Elective 2",
    "3736-MS"    => "MS",
    "3736-LANG"  => "Language",
    "3736-GSP"   => "GSP"
  }.freeze

  UNGROUPED_LABEL = "Ungrouped".freeze

  validates :course_id, uniqueness: { scope: :program_id }

  # Display label for a raw group code: constant first, raw suffix (prefix stripped)
  # for unknown codes, UNGROUPED_LABEL for blank.
  def self.group_label(code)
    return UNGROUPED_LABEL if code.blank?
    COURSE_GROUP_LABELS[code] || code.to_s.sub(/\A\d{4}-/, "")
  end

  # Sort key for ordering groups on the curriculum page: known codes in constant
  # order, then unknown codes alphabetically, then blank (Ungrouped) last.
  def self.group_sort_key(code)
    return [2, ""] if code.blank?
    idx = COURSE_GROUP_LABELS.keys.index(code)
    idx ? [0, idx.to_s.rjust(4, "0")] : [1, code.to_s]
  end

  def group_label
    self.class.group_label(course_group_code)
  end
end
