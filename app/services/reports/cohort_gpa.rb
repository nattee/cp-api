module Reports
  # "How did this class year do each semester?" — per-term GPS and GPAX
  # aggregates for one admission cohort of a program group.
  class CohortGpa < Base
    title    "Cohort GPA by semester"
    section  :students
    programs :all
    param    :program_group,  :program_group, required: true
    param    :admission_year, :academic_year, required: true, label: "Admission year (B.E.)"  # B.E.

    STATS = [ [ :avg, "avg" ], [ :sd, "SD" ], [ :min, "min" ], [ :max, "max" ],
              [ :minus2sd, "−2SD" ], [ :plus2sd, "+2SD" ] ].freeze

    def run
      group = ProgramGroup.find_by(code: program_group)
      return result(columns: columns, rows: [], summary: "Unknown program group.") unless group

      data = GradeStats::CohortGpa.call(program_group: group,
                                        admission_year_be: admission_year.to_i)

      rows = data[:terms].map do |t|
        row = { term: term_label(t), n: t[:gps][:n] }
        STATS.each do |key, _|
          row[:"gps_#{key}"]  = t[:gps][key]
          row[:"gpax_#{key}"] = t[:gpax][key]
        end
        row
      end

      result(
        columns: columns,
        rows: rows,
        summary: "#{group.code} #{admission_year} cohort — #{rows.size} semester(s)",
        chart: chart_data(data)
      )
    end

    private

    def columns
      [ { key: :term, label: "Term" }, { key: :n, label: "N" } ] +
        STATS.map { |key, sub| { key: :"gps_#{key}", label: "GPS #{sub}" } } +
        STATS.map { |key, sub| { key: :"gpax_#{key}", label: "GPAX #{sub}" } }
    end

    # Grades store C.E.; staff read terms in B.E.
    def term_label(t)
      "#{t[:year_ce] + 543}/#{t[:semester]}"
    end

    def chart_data(data)
      return nil if data[:terms].empty?
      {
        type: "gpa-trend",
        height: 320,
        caption: "GPS = GPA earned in that semester alone. GPAX = cumulative GPA through that semester. " \
                 "Shaded band = GPS average ± 2 SD (covers roughly 95% of the cohort).",
        data: {
          labels: data[:terms].map { |t| term_label(t) },
          datasets: [
            { label: "GPS +2SD", data: data[:terms].map { |t| t[:gps][:plus2sd] },  role: "band-upper" },
            { label: "GPS −2SD", data: data[:terms].map { |t| t[:gps][:minus2sd] }, role: "band-lower" },
            { label: "GPS avg",  data: data[:terms].map { |t| t[:gps][:avg] } },
            { label: "GPAX avg", data: data[:terms].map { |t| t[:gpax][:avg] }, dashed: true }
          ]
        }
      }
    end
  end
end
