require "json"

module Chulabooster
  MAPPERS = %w[Programs Courses Students ProgramCourses StudentCourses].freeze

  def self.mappers = MAPPERS.map { |name| Mappers.const_get(name).new }

  # Reads any prior checkpoint.json in run_dir to decide what to skip/resume. Completed entities are
  # inferred from the presence of each entity's *_local_only.csv (written only at completion).
  def self.load_checkpoint(run_dir)
    cp_path = File.join(run_dir, "checkpoint.json")
    completed = mappers.map(&:entity).select { |e| File.exist?(File.join(run_dir, "#{e}_local_only.csv")) }
    data = File.exist?(cp_path) ? JSON.parse(File.read(cp_path), symbolize_names: true) : {}
    in_progress = (data[:done] == false) ? data[:entity] : nil
    { completed: completed, in_progress: in_progress, next_cursor: data[:next_cursor] }
  end
end
