class Staff < ApplicationRecord
  STAFF_TYPES = %w[lecturer adjunct lab admin_permanent admin_annual admin_short_term].freeze

  STAFF_TYPE_ICONS = {
    "lecturer"         => "person",
    "adjunct"          => "person_add",
    "lab"              => "science",
    "admin_permanent"  => "badge",
    "admin_annual"     => "event_repeat",
    "admin_short_term" => "hourglass_bottom"
  }.freeze

  STATUSES = %w[active retired on_leave].freeze

  STATUS_ICONS = {
    "active"  => "check_circle",
    "retired" => "exit_to_app",
    "on_leave" => "pause_circle"
  }.freeze

  TITLES = %w[นาย นาง นางสาว].freeze

  ACADEMIC_TITLES = ["ศ.ดร.", "รศ.ดร.", "รศ.", "ผศ.ดร.", "ผศ.", "อ.ดร.", "ดร.", "อ."].freeze

  # Value object returned by #teaching_history — the career-wide teaching
  # matrix rendered on the staff show page.
  TeachingHistory = Struct.new(:semesters, :courses, :cells, :capped, keyword_init: true)

  has_many :staff_programs, dependent: :destroy
  has_many :programs, through: :staff_programs
  has_many :teachings, dependent: :restrict_with_error
  has_many :sections, through: :teachings

  validates :title, presence: true
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :staff_type, presence: true, inclusion: { in: STAFF_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :initials, uniqueness: true, allow_nil: true

  scope :active, -> { where(status: "active") }

  def full_name
    "#{first_name} #{last_name}"
  end

  def full_name_th
    return nil if first_name_th.blank? && last_name_th.blank?
    "#{first_name_th} #{last_name_th}"
  end

  def display_name
    parts = []
    parts << academic_title if academic_title.present?
    parts << full_name
    parts.join(" ")
  end

  def display_name_th
    return display_name if first_name_th.blank? && last_name_th.blank?
    parts = []
    parts << academic_title if academic_title.present?
    parts << full_name_th
    parts.join("")
  end

  def active?
    status == "active"
  end

  def retired?
    status == "retired"
  end

  def on_leave?
    status == "on_leave"
  end

  # Pivot of every Teaching this staff member has, for the Teaching History
  # card: rows = semesters actually taught in (newest first), columns =
  # courses merged across curriculum revisions by course_no (most-taught
  # first), cells = section numbers. The max_years window is anchored at the
  # most recent teaching — not today — so a retired lecturer still shows
  # their last active years.
  #
  #   semesters — [Semester] newest first, only terms with at least one teaching
  #   courses   — [{ course_no:, name:, course: }] by terms-taught desc, then
  #               course_no; :course is the latest revision taught (for linking)
  #   cells     — { [semester_id, course_no] => "1, 33" }
  #   capped    — true when older semesters were cut off by max_years
  #
  # Returns nil when the staff has never taught. max_years: nil = no cap.
  def teaching_history(max_years: 20)
    all = teachings.includes(section: { course_offering: [ :course, :semester ] }).to_a
    return nil if all.empty?

    semesters_all = all.map { |t| t.section.course_offering.semester }
                       .uniq.sort_by { |s| [ -s.year_be, -s.semester_number ] }
    semesters = semesters_all
    if max_years
      min_year = semesters_all.first.year_be - (max_years - 1)
      semesters = semesters_all.select { |s| s.year_be >= min_year }
    end

    visible_ids = semesters.map(&:id).to_set
    visible = all.select { |t| visible_ids.include?(t.section.course_offering.semester_id) }

    courses = visible.group_by { |t| t.section.course_offering.course.course_no }
                     .map do |course_no, ts|
                       latest = ts.map { |t| t.section.course_offering.course }.max_by(&:revision_year_be)
                       terms  = ts.map { |t| t.section.course_offering.semester_id }.uniq.size
                       [ terms, { course_no: course_no, name: latest.name, course: latest } ]
                     end
                     .sort_by { |terms, c| [ -terms, c[:course_no] ] }
                     .map(&:last)

    cells = visible.group_by { |t| [ t.section.course_offering.semester_id,
                                     t.section.course_offering.course.course_no ] }
                   .transform_values { |ts| ts.map { |t| t.section.section_number }.uniq.sort.join(", ") }

    TeachingHistory.new(semesters: semesters, courses: courses, cells: cells,
                        capped: semesters.size < semesters_all.size)
  end
end
