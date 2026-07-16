module Reports
  # Superclass for all reports. Provides a small class-level DSL so each report
  # is self-describing (drives both the menu and the param form), plus shared
  # instance helpers. Subclasses implement #run and return #result(...).
  class Base
    # ---- class-level DSL (plain class methods, like has_many/validates) ----
    def self.title(text = nil)
      text ? @title = text : @title
    end

    def self.section(sym = nil)
      sym ? @section = sym : @section
    end

    def self.programs(val = nil)
      val ? @programs = val : (@programs || :all)
    end

    def self.params_spec
      @params_spec ||= []
    end

    # Declares a parameter. Feeds the web form AND defines an instance reader.
    # type ∈ :course, :staff, :course_group, :academic_year, :teaching_year, :integer, :term, :semester_record, :program_group, :boolean
    # label: optional form-label override (default: humanized name)
    def self.param(name, type, required: false, label: nil)
      params_spec << { name: name, type: type, required: required, label: label }
      define_method(name) { @params[name.to_s] }
    end

    # Stable identifier used in URLs and the registry, e.g. "failing_students".
    def self.key
      name.demodulize.underscore
    end

    # Should this report appear for the given ProgramGroup?
    def self.applicable_to?(program_group)
      programs == :all || Array(programs).include?(program_group.code.to_sym)
    end

    def initialize(params = {})
      @params = params.transform_keys(&:to_s)
    end

    def run
      raise NotImplementedError, "#{self.class}#run must be implemented"
    end

    private

    # Builds the structured result. Columns must be declared by the caller for
    # clean headers (we do not infer, to keep labels precise for staff).
    def result(columns:, rows:, summary: nil, chart: nil, table_order: nil, warning: nil)
      Reports::Result.new(columns: columns, rows: rows, summary: summary, chart: chart,
                          table_order: table_order, warning: warning)
    end

    # Resolves a :semester_record param (a Semester id) to a Semester, defaulting
    # to the latest term when blank. Used by offering-based reports.
    def semester_scope
      sem_id = @params["semester"]
      sem_id.present? ? Semester.find_by(id: sem_id) : Semester.ordered.first
    end
  end
end
