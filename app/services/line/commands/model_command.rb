class Line::Commands::ModelCommand < Line::Commands::BaseCommand
  def execute(args)
    require_linked!

    model_key = args.strip.downcase
    available = LLM_CONFIG[:models]

    if model_key.blank?
      show_current(available)
    else
      switch_model(model_key, available)
    end
  end

  private

  def show_current(available)
    current = current_user.llm_model || LLM_CONFIG[:default_model].to_s
    current_label = available.dig(current.to_sym, :label) || current

    lines = ["Current model: #{current_label}"]
    lines << ""
    lines << "Available models:"
    available.each do |key, config|
      marker = key.to_s == current ? " (current)" : ""
      lines << "  #{key} - #{config[:label]}#{marker}"
    end
    lines << ""
    lines << "Switch with: model <name>"
    reply(lines.join("\n"))
  end

  def switch_model(model_key, available)
    unless available.key?(model_key.to_sym)
      names = available.keys.map(&:to_s).join(", ")
      reply("Unknown model \"#{model_key}\". Available: #{names}")
      return
    end

    current_user.update!(llm_model: model_key)
    label = available.dig(model_key.to_sym, :label)
    reply("Switched to #{label}.")
  end
end
