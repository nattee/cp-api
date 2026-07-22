class DevController < ApplicationController
  before_action :require_admin

  def styleguide; end
end
