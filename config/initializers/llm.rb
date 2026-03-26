# Loads config/llm.yml into a frozen hash accessible as LLM_CONFIG.
# Copy config/llm.yml.example to config/llm.yml before starting the app.
LLM_CONFIG = Rails.application.config_for(:llm).freeze
