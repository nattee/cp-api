module GradeStats
  # Shared numeric helpers for the grade statistics services. All GPA numbers
  # are rounded here (2 decimals) so web and LINE always show identical values.
  # SD is sample SD (n-1 denominator); nil when there are fewer than 2 values.
  module Stats
    module_function

    def mean(values)
      return nil if values.empty?
      (values.sum.to_f / values.size).round(2)
    end

    def sample_sd(values)
      raw_sample_sd(values)&.round(2)
    end

    # Full aggregate for cohort statistics: n, avg, sd, min, max, avg∓2sd.
    def aggregate(values)
      return { n: 0, avg: nil, sd: nil, min: nil, max: nil, minus2sd: nil, plus2sd: nil } if values.empty?

      m  = values.sum.to_f / values.size
      sd = raw_sample_sd(values)
      {
        n: values.size,
        avg: m.round(2),
        sd: sd&.round(2),
        min: values.min.round(2),
        max: values.max.round(2),
        minus2sd: sd ? (m - 2 * sd).round(2) : nil,
        plus2sd:  sd ? (m + 2 * sd).round(2) : nil
      }
    end

    def raw_sample_sd(values)
      return nil if values.size < 2
      m = values.sum.to_f / values.size
      Math.sqrt(values.sum { |v| (v - m)**2 } / (values.size - 1))
    end
  end
end
