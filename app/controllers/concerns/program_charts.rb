module ProgramCharts
  extend ActiveSupport::Concern

  private

  def prepare_admission_chart_data(students)
    all_counts = students.group(:admission_year_be, :enrollment_method).count
    years = all_counts.keys.map(&:first).uniq.sort
    methods = all_counts.keys.map(&:last).map { |m| m.presence || "Unknown" }.uniq.sort

    build_dataset = lambda { |counts|
      methods.each_with_object({}) do |method, hash|
        raw_key = method == "Unknown" ? nil : method
        hash[method] = years.map { |y| counts[[y, raw_key]] || 0 }
      end
    }

    datasets = { "all" => build_dataset.call(all_counts) }
    Student::STATUSES.each do |status|
      status_counts = students.where(status: status).group(:admission_year_be, :enrollment_method).count
      datasets[status] = build_dataset.call(status_counts)
    end

    @admission_chart_data = { labels: years, methods: methods, datasets: datasets }
  end

  def prepare_gpa_chart_data(program_ids)
    gpas = Grade.joins(:course, :student)
               .where(students: { program_id: program_ids })
               .where.not(grade_weight: nil)
               .group("grades.student_id")
               .pluck(Arel.sql("ROUND(SUM(grades.grade_weight * courses.credits) / SUM(courses.credits), 2)"))

    bin_edges = (0..7).map { |i| (i * 0.5).round(1) }
    labels = bin_edges.map { |lo| "#{format('%.1f', lo)}-#{format('%.1f', lo + 0.5)}" }
    counts = bin_edges.map do |lo|
      hi = lo + 0.5
      gpas.count { |g| g >= lo && (hi >= 4.0 ? g <= hi : g < hi) }
    end

    @gpa_chart_data = { labels: labels, counts: counts }
  end
end
