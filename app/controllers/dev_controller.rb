class DevController < ApplicationController
  skip_before_action :require_login

  before_action :ensure_development

  def styleguide; end

  private

  def ensure_development
    head :not_found unless Rails.env.development?
  end
end
