# Tool-selection eval for the LINE chatbot's LLM tools. Selection-only:
# scores which tool the model calls with which params; never executes tools.
#
# Usage:
#   bin/rails llm:eval                            # current registry, qwen, 3 repeats
#   bin/rails llm:eval MODEL=gemma                # other model (keys from config/llm.yml)
#   bin/rails llm:eval REGISTRY=candidate         # current + unregistered round-2 tools
#   bin/rails llm:eval N=5 CASES=room_week,none_greeting
#   bin/rails llm:eval SWEEP=1                    # breaking-point sweep across registry sizes
#
# Output: per-case console table + CSV under tmp/llm_eval/.
desc "Score LLM tool selection against test/llm_eval/cases.yml"
task "llm:eval" => :environment do
  require "csv"

  model = ENV.fetch("MODEL", "qwen")
  repeats = ENV.fetch("N", "3").to_i
  registry = ENV.fetch("REGISTRY", "current")

  cases = YAML.load_file(Rails.root.join("test/llm_eval/cases.yml"))
  if ENV["CASES"].present?
    wanted = ENV["CASES"].split(",").map(&:strip)
    cases = cases.select { |c| wanted.include?(c["id"]) }
    abort "No cases matched CASES=#{ENV['CASES']}" if cases.empty?
  end

  variants =
    if ENV["SWEEP"] == "1"
      # Registry sizes for the accuracy-vs-tool-count curve. With 7 shipped +
      # 4 candidate tools this yields roughly 7 / 11 / 16 / 24 definitions.
      [ [ "current", 0 ], [ "candidate", 0 ], [ "candidate", 5 ], [ "candidate", 13 ] ]
    else
      [ [ registry, 0 ] ]
    end

  timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
  out_dir = Rails.root.join("tmp/llm_eval")
  FileUtils.mkdir_p(out_dir)

  variants.each do |variant, decoy_count|
    definitions = LlmEval::RegistryBuilder.build(variant, decoy_count: decoy_count)
    label = decoy_count.zero? ? variant : "#{variant}+#{decoy_count}decoys"
    puts "", "=== #{label}: #{definitions.size} tools | model=#{model} | #{cases.size} cases × #{repeats} ==="

    runner = LlmEval::Runner.new(model_key: model, definitions: definitions, cases: cases, repeats: repeats)
    results = runner.call do |r|
      status = r[:tool_ok] ? (r[:params_ok] ? "PASS" : "tool-ok/params-MISS #{r[:misses].join(',')}") : "FAIL → #{r[:called_tool]}"
      puts format("  %-28s #%d %s", r[:case_id], r[:attempt], status)
    end

    csv_path = out_dir.join("#{timestamp}-#{model}-#{label}.csv")
    CSV.open(csv_path, "w") do |csv|
      csv << %w[case_id group attempt tool_count called_tool tool_ok params_ok misses]
      results.each do |r|
        csv << [ r[:case_id], r[:group], r[:attempt], definitions.size,
                 r[:called_tool], r[:tool_ok], r[:params_ok], r[:misses].join("|") ]
      end
    end

    puts "-" * 60
    %w[existing new none].each do |group|
      rows = results.select { |r| r[:group] == group }
      next if rows.empty?
      tool_pct = (100.0 * rows.count { |r| r[:tool_ok] } / rows.size).round(1)
      params_pct = (100.0 * rows.count { |r| r[:params_ok] } / rows.size).round(1)
      puts format("  %-10s tool %5.1f%%  tool+params %5.1f%%  (%d attempts)", group, tool_pct, params_pct, rows.size)
    end
    errors = results.count { |r| r[:called_tool].to_s.start_with?("ERROR") }
    puts "  transport errors: #{errors}" if errors.positive?
    puts "  CSV: #{csv_path}"
  end
end
