# Loads config/llm.yml into a frozen hash accessible as LLM_CONFIG.
# Copy config/llm.yml.example to config/llm.yml before starting the app.
LLM_CONFIG = Rails.application.config_for(:llm).freeze

unless LLM_CONFIG[:models].is_a?(Hash)
  raise <<~MSG
    LLM config is missing the `models:` key in config/llm.yml.
    The format changed — see config/llm.yml.example for the current structure.
  MSG
end
