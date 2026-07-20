# Writes the user's working term into the session. The term is a pure default
# for report forms (see TermContext), so this stores a value and nothing more —
# it never runs a report or redirects anywhere but back where the user was.
class TermContextsController < ApplicationController
  def update
    year = params[:year_be].presence
    if year && Semester.exists?(year_be: year)
      session[:term_context] = { "year_be" => year.to_i, "semester" => params[:semester].presence&.to_i }
    end
    redirect_back(fallback_location: root_path)
  end
end
